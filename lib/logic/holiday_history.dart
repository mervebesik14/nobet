import '../models/models.dart';

/// Yıllar arası bayram adaleti (saf Dart): aynı tatilin bir önceki
/// seferinde (önceki yıllardan en yakını) nöbet tutanlar bu sefer o
/// günlere en son yazılsın diye.
///
/// Tatil türü adından çıkar: "Kurban Bayramı 2. Gün" → "Kurban Bayramı",
/// "Cumhuriyet Bayramı Arifesi" → "Cumhuriyet Bayramı". Aynı güne düşen
/// iki tatil ("A / B") ikisine de sayılır. Yalnız tam gün tatiller.
class HolidayHistory {
  const HolidayHistory._();

  static final _suffix = RegExp(r'\s*(\d+\.\s*Gün|Arifesi)\s*$');

  /// Tatilin türleri.
  static Set<String> kindsOf(String name) => {
    for (final part in name.split(' / '))
      if (part.replaceAll(_suffix, '').trim() case final k when k.isNotEmpty) k,
  };

  /// [year]/[month]'ın tam gün tatil günü → aynı tatilin önceki seferinde
  /// nöbet tutanlar. Önceki seferin listesi yoksa o gün yer almaz.
  static Map<int, Set<String>> previousWorkers({
    required int year,
    required int month,
    required Iterable<Holiday> holidays,
    required Iterable<MonthPlan> plans,
  }) {
    final full = [
      for (final h in holidays)
        if (!h.isHalfDay) h,
    ];
    final byMonth = {for (final p in plans) p.key: p};
    Set<String> workersOn(DateTime d) {
      final plan = byMonth[MonthPlan.keyFor(d.year, d.month)];
      if (plan == null || !plan.hasRoster) return const {};
      return {...?plan.assignments[d.day]?.personIds};
    }

    final result = <int, Set<String>>{};
    for (final h in full) {
      if (h.date.year != year || h.date.month != month) continue;
      final workers = <String>{};
      for (final kind in kindsOf(h.name)) {
        final earlier = [
          for (final o in full)
            if (o.date.year < year && kindsOf(o.name).contains(kind)) o,
        ];
        if (earlier.isEmpty) continue;
        final lastYear = earlier
            .map((o) => o.date.year)
            .reduce((a, b) => a > b ? a : b);
        for (final o in earlier) {
          if (o.date.year == lastYear) workers.addAll(workersOn(o.date));
        }
      }
      if (workers.isNotEmpty) result[h.date.day] = workers;
    }
    return result;
  }
}
