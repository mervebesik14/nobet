/// Nöbetler arası boşluk hesabı (saf Dart).
///
/// Boşluk = iki ardışık nöbet arasındaki boş gün sayısı: 3 ve 8'inde nöbet
/// → 4, 5, 6, 7 → 4 gün. Arada izin (yıllık / şua / rapor) ya da pasif gün
/// varsa o aralık sayılmaz. Önceki ayın son günleri (0, -1, ...) da nöbet
/// günü olarak verilebilir; ay sonundan sonraki boşluk bilinmediği için
/// sayılmaz.
class ShiftGaps {
  const ShiftGaps._();

  /// Önerilen en fazla boşluk (gün).
  static const maxGap = 5;

  /// Dengelenen "uzun boşluk" aralığı: 4 ya da 5 gün.
  static const longGapMin = 4;
  static const longGapMax = 5;

  /// Sayılan boşluklar, sırayla: (önceki nöbet, sonraki nöbet, boş gün).
  static List<(int, int, int)> gaps(
    Iterable<int> days, {
    Set<int> absent = const {},
  }) {
    final sorted = days.toSet().toList()..sort();
    final out = <(int, int, int)>[];
    for (var i = 1; i < sorted.length; i++) {
      final a = sorted[i - 1];
      final b = sorted[i];
      if (b - a < 2) continue;
      var interrupted = false;
      for (var d = a + 1; d < b && !interrupted; d++) {
        interrupted = absent.contains(d);
      }
      if (!interrupted) out.add((a, b, b - a - 1));
    }
    return out;
  }

  /// [maxGap]'i aşan boşlukların toplam fazla günü (6 gün → 1).
  static int excess(Iterable<int> days, {Set<int> absent = const {}}) => gaps(
    days,
    absent: absent,
  ).fold(0, (s, g) => s + (g.$3 > maxGap ? g.$3 - maxGap : 0));

  /// 4 ya da 5 günlük boşluk sayısı.
  static int longCount(Iterable<int> days, {Set<int> absent = const {}}) =>
      gaps(
        absent: absent,
        days,
      ).where((g) => g.$3 >= longGapMin && g.$3 <= longGapMax).length;

  /// Tam [maxGap] (5) günlük boşluk sayısı. 5 günlük boşluk ya herkese eşit
  /// sayıda düşer ya da hiç kimseye.
  static int maxGapCount(Iterable<int> days, {Set<int> absent = const {}}) =>
      gaps(days, absent: absent).where((g) => g.$3 == maxGap).length;

  /// 5 günlük boşluk sayıları eşit değilse farkın büyüklüğü (eşitse 0).
  static int unevenMaxGaps(Iterable<int> counts) {
    if (counts.isEmpty) return 0;
    var lo = counts.first;
    var hi = counts.first;
    for (final c in counts) {
      if (c < lo) lo = c;
      if (c > hi) hi = c;
    }
    return hi - lo;
  }

  /// Hızlı tarama (algoritmanın puan hesabı için): [from]..[to] günlerini
  /// sırayla gezer, liste kopyalamaz / sıralamaz. ([excess], [longCount],
  /// [maxGapCount]) ile aynı sonucu verir.
  static (int excess, int long, int five) scan({
    required int from,
    required int to,
    required bool Function(int day) works,
    bool Function(int day)? isAbsent,
  }) {
    var excess = 0;
    var long = 0;
    var five = 0;
    int? last;
    for (var d = from; d <= to; d++) {
      if (works(d)) {
        if (last != null) {
          final gap = d - last - 1;
          if (gap > maxGap) excess += gap - maxGap;
          if (gap >= longGapMin && gap <= longGapMax) long++;
          if (gap == maxGap) five++;
        }
        last = d;
      } else if (isAbsent != null && isAbsent(d)) {
        // Araya izin girdi: aralık kesilir.
        last = null;
      }
    }
    return (excess, long, five);
  }

  /// En uzun boşluk (gün); sayılan boşluk yoksa null.
  static int? longest(Iterable<int> days, {Set<int> absent = const {}}) {
    int? best;
    for (final (_, _, gap) in gaps(days, absent: absent)) {
      if (best == null || gap > best) best = gap;
    }
    return best;
  }
}
