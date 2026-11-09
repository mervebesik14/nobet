import 'every_other_day_chains.dart';
import 'fatigue_score.dart';

/// Bir kişinin birden çok ay boyunca biriken nöbet toplamları.
class PersonTotals {
  const PersonTotals({
    this.shifts = 0,
    this.weekendShifts = 0,
    this.nationalHolidayShifts = 0,
    this.religiousHolidayShifts = 0,
    this.everyOtherDayPairs = 0,
    this.everyOtherDayChains = const [],
    this.consecutivePairs = 0,
    this.consecutiveWeekends = 0,
    this.longGaps = 0,
    this.dayShifts = 0,
    this.attendedDays = 0,
    this.workedHours = 0,
    this.requiredHours = 0,
    this.overtimeHours = 0,
    this.months = 0,
    this.availableDays = 0,
  });

  final int shifts;
  final int weekendShifts;

  /// Tam gün resmi (ulusal) tatil nöbetleri.
  final int nationalHolidayShifts;

  /// Tam gün dini bayram (Ramazan / Kurban) nöbetleri.
  final int religiousHolidayShifts;
  final int everyOtherDayPairs;

  /// Gün aşırı zincirler (ay ay; yıllık toplamda arka arkaya eklenir).
  final List<List<int>> everyOtherDayChains;

  /// Art arda (d, d+1) nöbet çifti sayısı.
  final int consecutivePairs;

  /// Art arda iki hafta sonunda da nöbet tutma sayısı.
  final int consecutiveWeekends;

  /// Yorgunluk puanı; bkz. [FatigueScore].
  double get fatigue => FatigueScore.of(this);

  /// Gün aşırı zincirlerdeki toplam nöbet günü.
  int get everyOtherDayDays =>
      everyOtherDayChains.fold(0, (s, c) => s + c.length);

  /// En uzun gün aşırı zincirin nöbet sayısı (zincir yoksa 0).
  int get longestChain =>
      everyOtherDayChains.fold(0, (m, c) => c.length > m ? c.length : m);

  /// Zincir uzunluğu → kaç tane, kısadan uzuna.
  Map<int, int> get chainCounts {
    final out = <int, int>{};
    for (final c in everyOtherDayChains) {
      out[c.length] = (out[c.length] ?? 0) + 1;
    }
    return Map.fromEntries(
      out.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
    );
  }

  /// "2'li × 3 · 3'lü × 1"; zincir yoksa boş.
  String get chainSummary => [
    for (final e in chainCounts.entries)
      '${EveryOtherDayChains.lengthLabel(e.key)} × ${e.value}',
  ].join(' · ');

  /// Nöbetler arası 4–5 günlük boşluk sayısı.
  final int longGaps;

  /// 7A (gündüz mesaisi) gün sayısı.
  final int dayShifts;

  /// Hastaneye geldiği gün sayısı (nöbet, 7A ya da ek mesai olan günler).
  final int attendedDays;
  final double workedHours;
  final double requiredHours;

  /// Ay ay hesaplanan fazla mesailerin toplamı (her ay max(0, ...)).
  final double overtimeHours;

  /// Toplama giren ay sayısı.
  final int months;

  /// Kişinin bu aylarda çalışabildiği gün sayısı: ayın günleri eksi izin,
  /// rapor, pasif ve işe başlamadan önceki günler. Yıl içi dengede kişinin
  /// payı buna göre hesaplanır.
  final int availableDays;

  PersonTotals operator +(PersonTotals o) => PersonTotals(
    shifts: shifts + o.shifts,
    weekendShifts: weekendShifts + o.weekendShifts,
    nationalHolidayShifts: nationalHolidayShifts + o.nationalHolidayShifts,
    religiousHolidayShifts: religiousHolidayShifts + o.religiousHolidayShifts,
    everyOtherDayPairs: everyOtherDayPairs + o.everyOtherDayPairs,
    everyOtherDayChains: [...everyOtherDayChains, ...o.everyOtherDayChains],
    consecutivePairs: consecutivePairs + o.consecutivePairs,
    consecutiveWeekends: consecutiveWeekends + o.consecutiveWeekends,
    longGaps: longGaps + o.longGaps,
    dayShifts: dayShifts + o.dayShifts,
    attendedDays: attendedDays + o.attendedDays,
    workedHours: workedHours + o.workedHours,
    requiredHours: requiredHours + o.requiredHours,
    overtimeHours: overtimeHours + o.overtimeHours,
    months: months + o.months,
    availableDays: availableDays + o.availableDays,
  );
}
