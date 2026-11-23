/// Ay başı (liste hazırlığı) adımları (saf Dart).
enum OpenStep {
  recurring('Kalıcı istekleri işle', 'Her ay tekrar eden istenmeyen günler.'),
  collect('İstek mesajını gönder', 'WhatsApp\'tan herkese; cevapları oku.'),
  replies('Cevapları takip et', 'Yazmayanlara hatırlat.'),
  check('Uygunluğu kontrol et', 'İzin çakışması, yetmeyen günler.'),
  generate('Listeyi oluştur', 'Kurallara göre adil liste.');

  const OpenStep(this.label, this.description);

  final String label;
  final String description;
}

/// Ay başı sihirbazının durumu (saf Dart).
class MonthOpen {
  const MonthOpen._();

  /// Yapılan adımların saklama anahtarı: `monthOpen/yyyy-aa`.
  static String key(int year, int month) =>
      'monthOpen/$year-${month.toString().padLeft(2, '0')}';

  /// Cevap verenlerin saklama anahtarı: `requestReplies/yyyy-aa`.
  static String repliesKey(int year, int month) =>
      'requestReplies/$year-${month.toString().padLeft(2, '0')}';

  static OpenStep? next(Set<OpenStep> done) {
    for (final s in OpenStep.values) {
      if (!done.contains(s)) return s;
    }
    return null;
  }

  static Set<OpenStep> fromNames(Iterable<Object?> names) => {
    for (final n in names)
      for (final s in OpenStep.values)
        if (s.name == n) s,
  };

  /// Cevap vermeyenlere hatırlatma mesajı.
  static String reminder(String monthLabel) =>
      'Merhaba, $monthLabel nöbet listesi için isteklerini bekliyorum. '
      'Nöbet tutamayacağın günler varsa gün numarasıyla yazar mısın? '
      'Yoksa "yok" yazman yeterli.';
}
