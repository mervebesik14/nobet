/// Gün aşırı nöbet zincirleri (saf Dart): ardışık iki nöbeti arasında tam
/// bir boş gün olan, en az iki nöbetlik en uzun diziler. Ör. 3-5-7 üçlü,
/// 10-12 ikili; 3-5-7-9 tek bir dörtlü zincirdir.
class EveryOtherDayChains {
  const EveryOtherDayChains._();

  /// [days] içindeki en uzun gün aşırı zincirler, güne göre sıralı.
  static List<List<int>> of(Iterable<int> days) {
    final set = days.toSet();
    final out = <List<int>>[];
    for (final d in [...set]..sort()) {
      // Zincirin başı: iki gün öncesinde nöbet yok.
      if (set.contains(d - 2) || !set.contains(d + 2)) continue;
      final chain = <int>[d];
      while (set.contains(chain.last + 2)) {
        chain.add(chain.last + 2);
      }
      out.add(chain);
    }
    return out;
  }

  /// Zincirlerdeki toplam gün sayısı (her gün bir kez).
  static int dayCount(Iterable<int> days) =>
      of(days).fold(0, (s, c) => s + c.length);

  /// Zincir uzunluğu → kaç tane (2'li, 3'lü, ...).
  static Map<int, int> countsByLength(Iterable<int> days) {
    final out = <int, int>{};
    for (final c in of(days)) {
      out[c.length] = (out[c.length] ?? 0) + 1;
    }
    return out;
  }

  /// En uzun zincirdeki nöbet sayısı; zincir yoksa 0.
  static int longest(Iterable<int> days) =>
      of(days).fold(0, (m, c) => c.length > m ? c.length : m);

  /// "2'li", "3'lü", "4'lü", "5'li", "6'lı" ...
  static String lengthLabel(int n) {
    const suffix = {
      0: "'lı",
      1: "'li",
      2: "'li",
      3: "'lü",
      4: "'lü",
      5: "'li",
      6: "'lı",
      7: "'li",
      8: "'li",
      9: "'lu",
    };
    final last = n % 10;
    if (n % 100 == 10 || n % 100 == 30) return "$n'lu";
    if (n % 100 == 20 || n % 100 == 50) return "$n'li";
    if (n % 100 == 40 || n % 100 == 60) return "$n'lı";
    return '$n${suffix[last]}';
  }

  /// "3-5-7"
  static String format(List<int> chain) => chain.join('-');
}
