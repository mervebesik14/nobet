import '../models/models.dart';
import 'turkish_collation.dart';
import 'turkish_dates.dart';

/// İstek türü.
enum RequestKind {
  unavailable('İstemediği gün'),
  leave('İzin'),
  shiftDay('Seçtiği nöbet günü'),
  overtime('Fazla mesai');

  const RequestKind(this.label);

  final String label;
}

/// Tek bir istek ve karşılanıp karşılanmadığı.
typedef RequestItem = ({int month, RequestKind kind, bool met, String detail});

/// Bir kişinin istekleri ve karşılanma oranı.
class PersonRequests {
  const PersonRequests({
    required this.personId,
    required this.name,
    required this.items,
  });

  final String personId;
  final String name;
  final List<RequestItem> items;

  int get total => items.length;
  int get met => items.where((i) => i.met).length;

  /// 0–100; isteği yoksa 100.
  int get percent => total == 0 ? 100 : (met * 100 / total).round();

  List<RequestItem> get unmet => [
    for (final i in items)
      if (!i.met) i,
  ];

  /// "İstemediği gün 12/12 · Fazla mesai 1/2"
  String get breakdown => [
    for (final kind in RequestKind.values)
      if (items.where((i) => i.kind == kind) case final list
          when list.isNotEmpty)
        '${kind.label} ${list.where((i) => i.met).length}/${list.length}',
  ].join(' · ');
}

/// Kişilerin isteklerinin (istemediği gün, izin, seçtiği nöbet günü, fazla
/// mesai) listede ne kadar karşılandığı (saf Dart). Fazla mesai isteği,
/// kişinin nöbet sayısı aynı roldeki istemeyenlerin ortalamasını aşınca
/// karşılanmış sayılır.
class RequestFulfillment {
  const RequestFulfillment._();

  /// [plan] ayındaki istekler, kişi → istekler. Listesi olmayan ay boştur.
  static Map<String, List<RequestItem>> forMonth(
    MonthPlan plan,
    Iterable<Person> people,
  ) {
    if (!plan.hasRoster) return const {};
    final m = plan.month;
    Set<int> daysOf(String id) => {
      for (final a in plan.assignments.values)
        if (a.includes(id)) a.day,
    };
    final out = <String, List<RequestItem>>{};
    void add(String id, RequestItem item) => (out[id] ??= []).add(item);

    for (final e in plan.unavailableDays.entries) {
      final days = daysOf(e.key);
      for (final d in {...e.value}.toList()..sort()) {
        add(e.key, (
          month: m,
          kind: RequestKind.unavailable,
          met: !days.contains(d),
          detail: '${formatDayMonth(d, m)} istemedi',
        ));
      }
    }
    for (final type in LeaveType.values) {
      for (final e in plan.leaveMap(type).entries) {
        if (e.value.isEmpty) continue;
        final days = daysOf(e.key);
        final clash = [
          for (final d in {...e.value}.toList()..sort())
            if (days.contains(d)) d,
        ];
        add(e.key, (
          month: m,
          kind: RequestKind.leave,
          met: clash.isEmpty,
          detail: clash.isEmpty
              ? '${type.label} (${e.value.length} gün)'
              : '${type.label} sırasında nöbet: '
                    '${clash.map((d) => formatDayMonth(d, m)).join(', ')}',
        ));
      }
    }
    for (final e in plan.requestedShifts.entries) {
      final days = daysOf(e.key);
      for (final d in {...e.value}.toList()..sort()) {
        add(e.key, (
          month: m,
          kind: RequestKind.shiftDay,
          met: days.contains(d),
          detail: '${formatDayMonth(d, m)} nöbet istedi',
        ));
      }
    }
    final byId = {for (final p in people) p.id: p};
    for (final id in plan.overtimeRequests) {
      final person = byId[id];
      if (person == null) continue;
      final peers = [
        for (final p in people)
          if (p.role == person.role &&
              !p.isChargeNurse &&
              p.id != id &&
              !plan.wantsOvertime(p.id) &&
              p.worksInMonth(plan.year, m))
            daysOf(p.id).length,
      ];
      final mine = daysOf(id).length;
      final average = peers.isEmpty
          ? null
          : peers.fold(0, (s, x) => s + x) / peers.length;
      final met = average == null || mine > average;
      add(id, (
        month: m,
        kind: RequestKind.overtime,
        met: met,
        detail:
            '$mine nöbet'
            '${average == null ? '' : ' (istemeyenlerin ortalaması '
                      '${_fmt(average)})'}',
      ));
    }
    return out;
  }

  /// [year] yılındaki (varsa [beforeMonth]'tan önceki) tüm istekler,
  /// kişi başına, ada göre sıralı.
  static List<PersonRequests> forYear({
    required int year,
    required Iterable<MonthPlan> plans,
    required Iterable<Person> people,
    int? beforeMonth,
  }) {
    final items = <String, List<RequestItem>>{};
    final sorted = [
      for (final p in plans)
        if (p.year == year && (beforeMonth == null || p.month < beforeMonth)) p,
    ]..sort((a, b) => a.month.compareTo(b.month));
    for (final plan in sorted) {
      for (final e in forMonth(plan, people).entries) {
        (items[e.key] ??= []).addAll(e.value);
      }
    }
    final names = {for (final p in people) p.id: p.name};
    return [
      for (final e in items.entries)
        PersonRequests(
          personId: e.key,
          name: names[e.key] ?? 'Silinmiş kişi',
          items: e.value,
        ),
    ]..sort((a, b) => compareTurkish(a.name, b.name));
  }

  /// [month]'tan önce bu yıl en son istediği fazla mesai karşılanmamış
  /// kişiler: bu ay yine isterlerse önce onlara fazla nöbet verilir.
  static Set<String> overtimePriority({
    required int year,
    required int month,
    required Iterable<MonthPlan> plans,
    required Iterable<Person> people,
  }) {
    final out = <String>{};
    for (final r in forYear(
      year: year,
      plans: plans,
      people: people,
      beforeMonth: month,
    )) {
      final overtime = [
        for (final i in r.items)
          if (i.kind == RequestKind.overtime) i,
      ];
      if (overtime.isNotEmpty && !overtime.last.met) out.add(r.personId);
    }
    return out;
  }

  static String _fmt(double v) => v == v.roundToDouble()
      ? v.toInt().toString()
      : v.toStringAsFixed(1).replaceAll('.', ',');
}
