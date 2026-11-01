import 'roster_generator.dart';
import 'roster_summary.dart';

/// Aday listeyi karşılaştırmak için ölçüler (saf Dart). Farklar rol grubu
/// içinde (sorumlu hemşire hariç) en çok ile en az arasındaki farktır;
/// birden çok rol varsa en kötüsü alınır. Hepsinde düşük daha iyi.
class RosterOptionStats {
  const RosterOptionStats({
    required this.missing,
    required this.shiftSpread,
    required this.weekendSpread,
    required this.everyOtherDayPairs,
    required this.longGaps,
    required this.score,
  });

  factory RosterOptionStats.of(RosterResult result, RosterSummary summary) {
    int spread(int Function(PersonSummary) value) {
      var worst = 0;
      final byRole = <Object, List<int>>{};
      for (final p in summary.people) {
        if (p.isChargeNurse) continue;
        (byRole[p.role] ??= []).add(value(p));
      }
      for (final values in byRole.values) {
        final d =
            values.reduce((a, b) => a > b ? a : b) -
            values.reduce((a, b) => a < b ? a : b);
        if (d > worst) worst = d;
      }
      return worst;
    }

    return RosterOptionStats(
      missing: result.issues.fold(0, (s, i) => s + i.missing),
      shiftSpread: spread((p) => p.shifts),
      weekendSpread: spread((p) => p.weekendShifts),
      everyOtherDayPairs: summary.people.fold(
        0,
        (s, p) => s + p.everyOtherDayPairs,
      ),
      longGaps: summary.people.fold(0, (s, p) => s + p.longGaps),
      score: result.score,
    );
  }

  /// Boş kalan koltuk sayısı (eksik gün raporu).
  final int missing;

  /// Toplam nöbet farkı.
  final int shiftSpread;

  /// Hafta sonu nöbeti farkı.
  final int weekendSpread;

  /// Toplam gün aşırı çift.
  final int everyOtherDayPairs;

  /// Toplam 4–5 günlük boşluk.
  final int longGaps;

  /// Üreticinin adalet puanı.
  final double score;

  /// Sıralama: önce eksik, sonra farklar, sonra puan.
  static int compare(RosterOptionStats a, RosterOptionStats b) {
    for (final (x, y) in [
      (a.missing, b.missing),
      (a.shiftSpread, b.shiftSpread),
      (a.weekendSpread, b.weekendSpread),
    ]) {
      if (x != y) return x.compareTo(y);
    }
    return a.score.compareTo(b.score);
  }

  /// En iyi adayın sırası.
  static int best(List<RosterOptionStats> options) {
    var best = 0;
    for (var i = 1; i < options.length; i++) {
      if (compare(options[i], options[best]) < 0) best = i;
    }
    return best;
  }
}
