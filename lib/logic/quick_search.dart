import '../models/models.dart';
import 'day_shift_planner.dart';
import 'request_parser.dart';
import 'turkish_collation.dart';
import 'turkish_dates.dart';

/// Arama sonucu: başlık ve satırlar; kişi ya da güne bağlı.
typedef SearchResult = ({
  String title,
  List<String> lines,
  String? personId,
  int? day,
});

/// Hızlı arama (saf Dart): "Ayşe", "12", "12 Aralık", "yarın", "Banu hafta
/// sonu", "Ayşe Banu" gibi sorguları seçili ayın listesinde çözer. Kişi
/// adı (ad ya da soyadın başı) kişinin nöbetlerini, izinlerini ve
/// isteklerini; gün o günün nöbetçilerini ve izinlilerini verir. İkisi
/// birlikteyse kişinin o günkü durumu yazılır.
class QuickSearch {
  const QuickSearch._();

  static List<SearchResult> run({
    required String query,
    required MonthPlan plan,
    required Iterable<Person> people,
    required DateTime today,
    Set<int> weekendDays = const {},
    Iterable<DayShift> dayShifts = const [],
  }) {
    final words = normalizeName(query)
        .replaceAll(RegExp(r"['’]\S*"), '')
        .split(RegExp(r'[\s,.;:]+'))
        .where((w) => w.isNotEmpty)
        .toList();
    if (words.isEmpty) return const [];
    final month = plan.month;
    final last = plan.daysInMonth;
    final days = <int>{};
    final notes = <String>[];
    var weekendOnly = false;
    final nameWords = <String>[];
    final monthWords = [for (final m in turkishMonthNames) turkishLowerCase(m)];
    for (var i = 0; i < words.length; i++) {
      final w = words[i];
      if (w == 'bugün' || w == 'yarın') {
        final d = w == 'bugün'
            ? today
            : DateTime(today.year, today.month, today.day + 1);
        if (d.year == plan.year && d.month == month) {
          days.add(d.day);
        } else {
          notes.add('${w == 'bugün' ? 'Bugün' : 'Yarın'} seçili ayda değil.');
        }
      } else if (w == 'hafta' &&
          i + 1 < words.length &&
          words[i + 1] == 'sonu') {
        weekendOnly = true;
        i++;
      } else if (int.tryParse(w) case final n?) {
        if (n >= 1 && n <= last) days.add(n);
      } else if (monthWords.indexOf(w) case final m when m >= 0) {
        if (m + 1 != month) {
          notes.add(
            'Yalnız seçili ay (${turkishMonthNames[month - 1]}) aranır.',
          );
        }
      } else {
        nameWords.add(w);
      }
    }

    final active = [
      for (final p in people)
        if (p.worksInMonth(plan.year, month) ||
            plan.assignments.values.any((a) => a.includes(p.id)))
          p,
    ]..sort((a, b) => compareTurkish(a.name, b.name));
    final matched = <Person>[];
    for (final w in nameWords) {
      for (final p in active) {
        final parts = normalizeName(p.name).split(' ');
        if (parts.any((x) => x.startsWith(w)) && !matched.contains(p)) {
          matched.add(p);
        }
      }
    }
    final byId = {for (final p in people) p.id: p};
    String name(String id) => byId[id]?.name ?? 'Silinmiş kişi';
    String date(int d) => formatDayMonthWeekday(plan.year, month, d);
    final dayShiftOn = {for (final s in dayShifts) (s.personId, s.day)};

    String? statusOn(String id, int d) {
      final a = plan.assignments[d];
      if (a != null && a.includes(id)) return '${a.shiftCode(id)} nöbette';
      if (dayShiftOn.contains((id, d))) return '7A';
      for (final t in LeaveType.values) {
        if (plan.leaveOf(id, t).contains(d)) return t.label;
      }
      if (plan.unavailableDaysOf(id).contains(d)) return 'istemediği gün';
      return null;
    }

    final results = <SearchResult>[];
    if (matched.isNotEmpty) {
      for (final p in matched) {
        final shifts = [
          for (var d = 1; d <= last; d++)
            if (plan.assignments[d]?.includes(p.id) ?? false)
              if (!weekendOnly || weekendDays.contains(d)) d,
        ];
        final lines = <String>[
          if (days.isNotEmpty)
            for (final d in days.toList()..sort())
              '${date(d)}: ${statusOn(p.id, d) ?? 'boş'}',
          if (days.isEmpty) ...[
            shifts.isEmpty
                ? (weekendOnly
                      ? 'Bu ay hafta sonu nöbeti yok.'
                      : 'Bu ay nöbeti yok.')
                : '${weekendOnly ? 'Hafta sonu nöbetleri' : 'Nöbetler'} '
                      '(${shifts.length}): ${[for (final d in shifts) _code(plan, p.id, d)].join(', ')}',
            if (!weekendOnly) ...[
              for (final t in LeaveType.values)
                if (plan.leaveOf(p.id, t).isNotEmpty)
                  '${t.label}: ${RequestParser.compactDays(plan.leaveOf(p.id, t))}',
              if (plan.unavailableDaysOf(p.id).isNotEmpty)
                'İstemediği günler: '
                    '${RequestParser.compactDays(plan.unavailableDaysOf(p.id))}',
              if (plan.preferredDaysOf(p.id).isNotEmpty)
                'Tercih: ${RequestParser.compactDays(plan.preferredDaysOf(p.id))}',
            ],
          ],
        ];
        results.add((
          title: '${p.name} · ${p.role.label}',
          lines: lines,
          personId: p.id,
          day: days.length == 1 ? days.single : null,
        ));
      }
    } else {
      final list = days.isNotEmpty
          ? (days.toList()..sort())
          : weekendOnly
          ? (weekendDays.where((d) => d <= last).toList()..sort())
          : const <int>[];
      for (final d in list) {
        final a = plan.assignments[d];
        final lines = <String>[
          if (a == null || a.personIds.isEmpty)
            'Nöbetçi yazılmamış.'
          else
            'Nöbetçi: ${[for (final id in a.personIds) '${name(id)} (${a.shiftCode(id)})'].join(', ')}',
          if ([
                for (final s in dayShifts)
                  if (s.day == d) name(s.personId),
              ]
              case final day7 when day7.isNotEmpty)
            '7A: ${day7.join(', ')}',
          if ([
                for (final p in active)
                  for (final t in LeaveType.values)
                    if (plan.leaveOf(p.id, t).contains(d))
                      '${p.name} (${t.label})',
              ]
              case final off when off.isNotEmpty)
            'İzinli: ${off.join(', ')}',
        ];
        results.add((title: date(d), lines: lines, personId: null, day: d));
      }
    }
    if (notes.isNotEmpty && results.isNotEmpty) {
      final first = results.first;
      results[0] = (
        title: first.title,
        lines: [...first.lines, ...notes],
        personId: first.personId,
        day: first.day,
      );
    }
    return results;
  }

  /// "12" ya da vardiya 24 değilse "12 (16A)".
  static String _code(MonthPlan plan, String id, int d) {
    final code = plan.assignments[d]!.shiftCode(id);
    return code == '24' ? '$d' : '$d ($code)';
  }
}
