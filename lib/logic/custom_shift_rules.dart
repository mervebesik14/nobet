import '../models/custom_shift.dart';

/// Özel mesai tanımının denetimi (saf Dart).
class CustomShiftRules {
  const CustomShiftRules._();

  /// En uzun ad (tablo hücresine sığsın).
  static const maxCodeLength = 4;

  /// Süre sınırları (saat).
  static const minHours = 0.5;
  static const maxHours = 24.0;

  /// Başlangıç ve bitişten süre (saat); bitiş başlangıçtan önce ya da
  /// eşitse ertesi gün sayılır (13:00 → 08:00 = 19, 08:00 → 08:00 = 24).
  static double hoursBetween(int startMinute, int endMinute) {
    var diff = (endMinute - startMinute) % (24 * 60);
    if (diff == 0) diff = 24 * 60;
    return diff / 60;
  }

  /// Kullanıcının yazdığı süre ("19", "7,5") → saat; anlaşılmazsa null.
  static double? parseHours(String text) =>
      double.tryParse(text.trim().replaceAll(',', '.'));

  /// Tanımdaki hata; geçerliyse null. [existing] öteki tanımlar (düzenlenen
  /// hariç).
  static String? error({
    required String code,
    required double? hours,
    required Iterable<CustomShift> existing,
  }) {
    final c = CustomShift.normalize(code);
    if (c.isEmpty) return 'Mesai adı girin (ör. 19A).';
    if (c.length > maxCodeLength) {
      return 'Ad en fazla $maxCodeLength karakter olsun.';
    }
    if (CustomShift.reserved.contains(c) || RegExp(r'^\d+$').hasMatch(c)) {
      return '"$c" hazır bir vardiya ya da sayı; başka bir ad seçin.';
    }
    if (existing.any((s) => s.code == c)) return '"$c" zaten tanımlı.';
    if (hours == null) return 'Süreyi saat olarak girin (ör. 19).';
    if (hours < minHours || hours > maxHours) {
      return 'Süre ${minHours.toString().replaceAll('.', ',')}–'
          '${maxHours.toInt()} saat arasında olsun.';
    }
    return null;
  }
}
