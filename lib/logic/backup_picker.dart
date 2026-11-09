import '../models/models.dart';
import 'block_reason.dart';
import 'every_other_day_chains.dart';
import 'turkish_collation.dart';
import 'turkish_dates.dart';

/// Günün yedek nöbetçileri (saf Dart): o gün nöbette olmayan, aynı roldeki
/// kişilerden biri gelemezse yerine kural bozmadan yazılabilecekler. Kesin
/// kurallar: izin / istemediği gün / pasif (bkz. [BlockReason]), art arda
/// gün, gün aşırı zincir sınırı; sorumlu hemşire yedek olmaz. Sıra: bu ay
/// en az nöbeti olan, eşitse (hafta sonuysa) en az hafta sonu tutan.
class BackupPicker {
  const BackupPicker._();

  static List<Person> candidates({
    required MonthPlan plan,
    required Iterable<Person> people,
    required int day,
    required Role role,
    required RosterSettings settings,
    Map<String, Map<int, BlockReason>> blockReasons = const {},
    Set<int> weekendDays = const {},
    int count = 2,
  }) {
    final current = plan.assignments[day];
    Set<int> daysOf(String id) => {
      for (final a in plan.assignments.values)
        if (a.includes(id)) a.day,
    };
    final out = <(Person, int, int)>[];
    for (final p in people) {
      if (p.role != role ||
          p.isChargeNurse ||
          !p.worksInMonth(plan.year, plan.month) ||
          (current?.includes(p.id) ?? false) ||
          blockReasons[p.id]?[day] != null) {
        continue;
      }
      final days = daysOf(p.id);
      if (settings.forbidConsecutiveDays &&
          (days.contains(day - 1) || days.contains(day + 1))) {
        continue;
      }
      final chain = EveryOtherDayChains.of({
        ...days,
        day,
      }).where((c) => c.contains(day)).fold(1, (m, c) => c.length);
      if (chain > settings.maxEveryOtherDayChain) continue;
      out.add((p, days.length, days.where(weekendDays.contains).length));
    }
    final weekend = weekendDays.contains(day);
    out.sort((a, b) {
      final s = a.$2.compareTo(b.$2);
      if (s != 0) return s;
      if (weekend) {
        final w = a.$3.compareTo(b.$3);
        if (w != 0) return w;
      }
      return compareTurkish(a.$1.name, b.$1.name);
    });
    return [for (final e in out.take(count)) e.$1];
  }

  /// Yedeğe gidecek mesaj.
  static String message({
    required MonthPlan plan,
    required int day,
    required String backupName,
    required String absentName,
    String shift = '24',
  }) =>
      'Merhaba $backupName, '
      '${formatDayMonthWeekday(plan.year, plan.month, day)} günü '
      '$absentName gelemiyor; yerine $shift nöbeti senin. '
      'Uygun değilsen lütfen hemen haber ver.';
}
