import '../models/models.dart';
import 'yearly_summary.dart';

/// Bir kişinin yıl sonu tahmini.
typedef ProjectionRow = ({
  String personId,
  String name,
  Role role,
  int shifts,

  /// Şu an payından farkı (+ fazla tutmuş).
  double diffNow,

  /// Bu hızla giderse yıl sonunda payından farkı.
  double diffEnd,

  /// Yıl sonunda eşitlenmek için kalan aylarda tutması gereken nöbet.
  double needed,
});

/// Yıl sonu tahmini (saf Dart): bugüne kadarki nöbetler kişinin
/// çalışabildiği güne göre payıyla karşılaştırılır; herkes kendi hızıyla
/// devam ederse yıl sonunda kim payının ne kadar üstünde / altında kalır,
/// eşitlenmek için kalan aylarda kaç nöbet tutması gerekir. Rol içinde,
/// sorumlu hemşire hariç. Kalan günlerde herkes çalışabilir sayılır.
class YearProjection {
  const YearProjection._();

  /// Bu kadar ya da fazla fark dikkat çekici sayılır.
  static const notable = 1.5;

  static List<ProjectionRow> build({
    required YearlySummary summary,
    required int year,
  }) {
    if (summary.months.isEmpty) return const [];
    final last = summary.months.reduce((a, b) => a > b ? a : b);
    final future = DateTime(
      year + 1,
    ).difference(DateTime(year, last + 1)).inDays;
    // Hız yalnız listesi olan ayların günlerine göre: uygulama yıl ortasında
    // kullanılmaya başlandıysa önceki aylar hızı düşürmesin.
    final covered = summary.months.toSet().fold(
      0,
      (s, m) => s + DateTime(year, m + 1, 0).day,
    );
    final out = <ProjectionRow>[];
    for (final role in Role.values) {
      final group = [
        for (final r in summary.rows)
          if (r.role == role && !r.isChargeNurse) r,
      ];
      if (group.length < 2) continue;
      final sumShifts = group.fold(0, (s, r) => s + r.totals.shifts);
      final sumAvail = group.fold(0, (s, r) => s + r.totals.availableDays);
      if (sumAvail == 0) continue;
      // Grubun günlük nöbet hızı (takvim gününe göre): kalan günlerde
      // tutulacak toplam nöbet tahmini.
      final groupRate = sumShifts / covered;
      final endTotal = sumShifts + groupRate * future;
      final endAvail = sumAvail + group.length * future;
      for (final r in group) {
        final t = r.totals;
        final shareNow = sumShifts * t.availableDays / sumAvail;
        final rate = t.availableDays == 0 ? 0 : t.shifts / t.availableDays;
        final projected = t.shifts + rate * future;
        final shareEnd = endTotal * (t.availableDays + future) / endAvail;
        // Herkes kendi hızıyla: yıl sonu toplamı farklı çıkabilir; fark
        // grubun ortalama hızına göre ölçeklenir.
        final projectedTotal = group.fold(
          0.0,
          (s, g) =>
              s +
              g.totals.shifts +
              (g.totals.availableDays == 0
                      ? 0
                      : g.totals.shifts / g.totals.availableDays) *
                  future,
        );
        final scaled = projectedTotal == 0
            ? projected
            : projected * endTotal / projectedTotal;
        out.add((
          personId: r.personId,
          name: r.name,
          role: role,
          shifts: t.shifts,
          diffNow: t.shifts - shareNow,
          diffEnd: scaled - shareEnd,
          needed: (shareEnd - t.shifts) < 0 ? 0 : shareEnd - t.shifts,
        ));
      }
    }
    return out;
  }

  /// "+1,5" / "−2" / "0".
  static String signed(double v) {
    final r = (v * 10).round() / 10;
    if (r == 0) return '0';
    final s = r == r.roundToDouble()
        ? r.abs().toInt().toString()
        : r.abs().toStringAsFixed(1).replaceAll('.', ',');
    return r > 0 ? '+$s' : '−$s';
  }
}
