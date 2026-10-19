import 'person_totals.dart';

/// Yıllık özette aylara göre karşılaştırılan bir ölçü.
class YearlyMetric {
  const YearlyMetric(this.label, this.pick);

  final String label;
  final num Function(PersonTotals) pick;
}

/// Yıllık özet raporlarının (PDF, Excel) ortak parçaları (saf Dart).
class YearlyReport {
  const YearlyReport._();

  /// Aylara göre karşılaştırmada gösterilen ölçüler, ekrandaki sırayla.
  static final metrics = [
    YearlyMetric('Nöbet', (t) => t.shifts),
    YearlyMetric('Dini bayram nöbeti', (t) => t.religiousHolidayShifts),
    YearlyMetric('Fazla mesai (saat)', (t) => t.overtimeHours),
    YearlyMetric('Hafta sonu nöbeti', (t) => t.weekendShifts),
    YearlyMetric('Resmi tatil nöbeti', (t) => t.nationalHolidayShifts),
    YearlyMetric('4–5 gün ara', (t) => t.longGaps),
  ];

  /// Bu kadar farkın altı "ortalamaya yakın" sayılır (renksiz).
  static const neutral = 0.5;

  /// Renk bu farkta en koyu olur.
  static const full = 2.0;

  static const _above = 0xE34948;
  static const _below = 0x2A78D6;

  /// Ortalamadan farka göre hücre rengi (0xRRGGBB, beyaz zemine karışık):
  /// kırmızı = ortalamanın üstü, mavi = altı; yakınsa ya da kayıt yoksa null.
  /// Ekrandaki karşılaştırma tablosuyla aynı ölçek.
  static int? tint(double? deviation) {
    if (deviation == null || deviation.abs() < neutral) return null;
    final strength = ((deviation.abs() - neutral) / (full - neutral)).clamp(
      0.0,
      1.0,
    );
    final alpha = 0.18 + 0.32 * strength;
    final base = deviation > 0 ? _above : _below;
    int mix(int shift) {
      final c = (base >> shift) & 0xFF;
      return (255 + (c - 255) * alpha).round() & 0xFF;
    }

    return (mix(16) << 16) | (mix(8) << 8) | mix(0);
  }
}
