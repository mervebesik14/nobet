/// Ay kapanışının adımları (saf Dart).
enum CloseStep {
  check(
    'Listeyi kontrol et',
    'Eksik koltuk, kural uyarıları, ücret saat sınırını aşanlar.',
  ),
  lock('Listeyi kilitle', 'Kapanıştan sonra yanlışlıkla değişmesin.'),
  publish('Herkese gönder', 'Herkese kendi listesi WhatsApp\'tan.'),
  overtime('Fazla mesai raporu', 'İmzaya hazır PDF.'),
  personal('Kişisel PDF\'ler', 'Herkesin kendi listesi, tek paylaşımda.'),
  backup('Yedek al', 'Bütün verinin yedek dosyası.');

  const CloseStep(this.label, this.description);

  final String label;
  final String description;
}

/// Ayın kapanış durumu ve kontrol özeti (saf Dart).
class MonthClose {
  const MonthClose._();

  /// Saklama anahtarı: `monthClose/yyyy-aa`.
  static String key(int year, int month) =>
      'monthClose/$year-${month.toString().padLeft(2, '0')}';

  /// Henüz yapılmamış ilk adım; hepsi bittiyse null.
  static CloseStep? next(Set<CloseStep> done) {
    for (final s in CloseStep.values) {
      if (!done.contains(s)) return s;
    }
    return null;
  }

  /// Kaydedilmiş adlardan adımlar (tanınmayanlar atlanır).
  static Set<CloseStep> fromNames(Iterable<Object?> names) => {
    for (final n in names)
      for (final s in CloseStep.values)
        if (s.name == n) s,
  };

  /// Kontrol satırları; sorun yoksa tek satır "Her şey yolunda".
  static List<String> checkLines({
    required int missingSeats,
    required int violations,
    required List<String> overCapNames,
    required int payHourCap,
  }) {
    final lines = [
      if (missingSeats > 0) '$missingSeats koltuk boş.',
      if (violations > 0) '$violations kural uyarısı var.',
      if (overCapNames.isNotEmpty)
        'Ücretli $payHourCap saat sınırını aşanlar: ${overCapNames.join(', ')}.',
    ];
    return lines.isEmpty ? const ['Her şey yolunda.'] : lines;
  }
}
