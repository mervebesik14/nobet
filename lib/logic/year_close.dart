import '../models/models.dart';
import 'holiday_history.dart';
import 'turkish_collation.dart';
import 'turkish_dates.dart';

/// Yıl kapanışının adımları (saf Dart).
enum YearStep {
  summary('Yıllık özet', 'Kim kaç nöbet, hafta sonu, bayram tuttu (PDF).'),
  reports('Herkesin karnesi', 'Kişi başı yıllık karne, tek paylaşımda.'),
  leave('İzin bakiyeleri', 'Kullanılan ve kalan yıllık izin.'),
  holidays(
    'Gelecek yılın bayram planı',
    'Bu yıl tutanlar sonraki sefer en son.',
  ),
  backup('Yedek al', 'Bütün verinin yedek dosyası.');

  const YearStep(this.label, this.description);

  final String label;
  final String description;
}

/// Gelecek yılın bir tatili ve bu yıl aynı tatilde nöbet tutanlar.
typedef HolidayTurn = ({String kind, String dates, List<String> lastWorkers});

/// Yıl kapanışı (saf Dart).
class YearClose {
  const YearClose._();

  static String key(int year) => 'yearClose/$year';

  static YearStep? next(Set<YearStep> done) {
    for (final s in YearStep.values) {
      if (!done.contains(s)) return s;
    }
    return null;
  }

  static Set<YearStep> fromNames(Iterable<Object?> names) => {
    for (final n in names)
      for (final s in YearStep.values)
        if (s.name == n) s,
  };

  /// Gelecek yılın ([nextHolidays]) tam gün tatilleri, türüne göre; bu yıl
  /// ([year]) aynı tatilde nöbet tutanlar ([plans]'tan) ile. Sıra tarihe
  /// göre.
  static List<HolidayTurn> holidayTurns({
    required int year,
    required Iterable<Holiday> thisYear,
    required Iterable<Holiday> nextHolidays,
    required Iterable<MonthPlan> plans,
    required String Function(String) name,
  }) {
    final byMonth = {for (final p in plans) p.key: p};
    Set<String> workersOn(DateTime d) => {
      ...?byMonth[MonthPlan.keyFor(d.year, d.month)]
          ?.assignments[d.day]
          ?.personIds,
    };
    final groups = <String, List<DateTime>>{};
    for (final h in nextHolidays) {
      if (h.isHalfDay || h.date.year != year + 1) continue;
      for (final k in HolidayHistory.kindsOf(h.name)) {
        (groups[k] ??= []).add(h.date);
      }
    }
    final out = <HolidayTurn>[];
    for (final e in groups.entries) {
      final dates = e.value..sort();
      final last = <String>{};
      for (final h in thisYear) {
        if (h.isHalfDay || h.date.year != year) continue;
        if (HolidayHistory.kindsOf(h.name).contains(e.key)) {
          last.addAll(workersOn(h.date));
        }
      }
      final first = dates.first, end = dates.last;
      final label = first == end
          ? '${first.day} ${turkishMonthNames[first.month - 1]}'
          : first.month == end.month
          ? '${first.day}–${end.day} ${turkishMonthNames[end.month - 1]}'
          : '${first.day} ${turkishMonthNames[first.month - 1]} – '
                '${end.day} ${turkishMonthNames[end.month - 1]}';
      out.add((
        kind: e.key,
        dates: label,
        lastWorkers: [for (final id in last) name(id)]..sort(compareTurkish),
      ));
    }
    out.sort((a, b) => groups[a.kind]!.first.compareTo(groups[b.kind]!.first));
    return out;
  }

  /// Paylaşılacak bayram planı metni.
  static String holidayText(int year, List<HolidayTurn> turns) => [
    '${year + 1} bayram ve tatil planı',
    'Bu yıl aynı tatilde nöbet tutanlar gelecek sefer o günlere en son '
        'yazılır.',
    for (final t in turns)
      '• ${t.kind} (${t.dates}): '
          '${t.lastWorkers.isEmpty ? '$year kaydı yok' : '$year\'de tutanlar: ${t.lastWorkers.join(', ')}'}',
  ].join('\n');
}
