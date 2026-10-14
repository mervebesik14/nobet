import 'package:flutter/material.dart';

/// Uygulama genelinde kullanılan yumuşak, tema uyumlu arka plan tonları.
///
/// Parlak `...Container` renkleri yerine, marka renginin yüzeye düşük oranda
/// karıştırılmasıyla elde edilen hafif tonlar kullanılır; hem açık hem koyu
/// temada göz yormaz ve tablo gibi çok renkli alanlarda uyum sağlar.
extension AppTints on ColorScheme {
  Color _tint(Color color, double opacity) =>
      Color.alphaBlend(color.withValues(alpha: opacity), surface);

  /// Hafta sonu sütunları: çok hafif marka tonu.
  Color get weekendTint => _tint(primary, 0.08);

  /// Resmi tatil sütunları: hafif, sıcak vurgu (hafta sonundan ayrışır).
  Color get holidayTint => _tint(const Color(0xFFE0A030), 0.16);

  /// Rol grubu başlığı şeridi.
  Color get groupTint => _tint(primary, 0.14);

  /// Bilgi/özet kartı zemini.
  Color get infoTint => _tint(primary, 0.08);

  /// Üzerinde koyu metin okunur bir vurgu zemini (başlık satırları).
  Color get headerTint => surfaceContainerHigh;

  /// Uyarı/eksik/ihlal zemini: hafif kırmızı ton.
  Color get dangerTint => _tint(error, 0.10);

  /// Yıllık izin günleri: istenmeyen günlerden (kırmızı) ayrışan serin ton.
  Color get leaveColor => const Color(0xFF2E7D8A);

  /// Yıllık izin lejantı/zemini: serin tonun hafif hali.
  Color get leaveTint => _tint(leaveColor, 0.16);

  /// Şua izni günleri: yıllık izinden ayrışan mor ton.
  Color get radiationColor => const Color(0xFF7E57C2);

  /// Şua izni lejantı/zemini: mor tonun hafif hali.
  Color get radiationTint => _tint(radiationColor, 0.16);

  /// 7A (gündüz mesaisi) yazısı: sıcak, nöbetten ayrışan ton.
  Color get dayShiftColor => const Color(0xFFB26A00);

  /// 7A hücresi zemini.
  Color get dayShiftTint => _tint(dayShiftColor, 0.14);
}
