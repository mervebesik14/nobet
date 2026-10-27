/// Türkçe alfabe sırasıyla metin karşılaştırma ve normalleştirme.
///
/// Dart'ın `compareTo`'su kod birimine göre sıralar; "Çiğdem" "Zeynep"ten
/// sonra gelir. Burada ç, ğ, ı, ö, ş, ü kendi harflerinin hemen ardından
/// gelir ve büyük/küçük harf ayrımı yapılmaz (İ→i, I→ı).
library;

const _alphabet = 'abcçdefgğhıijklmnoöprsştuüvyz';

/// Türkçe kurallarla küçük harfe çevirir (I→ı, İ→i).
String turkishLowerCase(String text) =>
    text.replaceAll('I', 'ı').replaceAll('İ', 'i').toLowerCase();

/// Türkçe kurallarla büyük harfe çevirir (i→İ, ı→I).
String turkishUpperCase(String text) =>
    text.replaceAll('i', 'İ').replaceAll('ı', 'I').toUpperCase();

/// Karşılaştırma ve tekrar kontrolü için: kırpılmış, boşlukları tekleşmiş,
/// Türkçe küçük harfli metin.
String normalizeName(String name) =>
    turkishLowerCase(name.trim().replaceAll(RegExp(r'\s+'), ' '));

int _rank(int rune) {
  final i = _alphabet.indexOf(String.fromCharCode(rune));
  // Alfabe dışı karakterler (boşluk, rakam, yabancı harf) kod birimine göre;
  // boşluk ve rakamlar harflerden önce gelir.
  if (i >= 0) return 1000 + i;
  return rune < 128 && !_isAsciiLetter(rune) ? rune : 2000 + rune;
}

bool _isAsciiLetter(int r) => (r >= 65 && r <= 90) || (r >= 97 && r <= 122);

/// [a] ve [b]'yi Türkçe alfabe sırasıyla karşılaştırır, büyük/küçük harf
/// duyarsız. Harfleri aynı olanlar kendi aralarında kararlı sıralansın diye
/// sonda kod birimiyle karşılaştırılır.
int compareTurkish(String a, String b) {
  final ra = turkishLowerCase(a).runes.toList();
  final rb = turkishLowerCase(b).runes.toList();
  final n = ra.length < rb.length ? ra.length : rb.length;
  for (var i = 0; i < n; i++) {
    final c = _rank(ra[i]).compareTo(_rank(rb[i]));
    if (c != 0) return c;
  }
  final c = ra.length.compareTo(rb.length);
  return c != 0 ? c : a.compareTo(b);
}
