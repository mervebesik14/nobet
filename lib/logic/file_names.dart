/// Dosya adı için güvenli kısa ad (saf Dart): Türkçe harfler ASCII'ye
/// çevrilir, küçük harf, harf/rakam dışı her şey tek tireye iner.
/// "Merve Beşik" → "merve-besik".
String fileSlug(String text) {
  const map = {
    'ç': 'c', 'Ç': 'c', 'ğ': 'g', 'Ğ': 'g', 'ı': 'i', 'I': 'i', 'İ': 'i', //
    'ö': 'o', 'Ö': 'o', 'ş': 's', 'Ş': 's', 'ü': 'u', 'Ü': 'u',
  };
  final ascii = [
    for (final ch in text.split('')) map[ch] ?? ch.toLowerCase(),
  ].join();
  final slug = ascii
      .replaceAll(RegExp('[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  return slug.isEmpty ? 'kisi' : slug;
}
