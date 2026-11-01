/// Telefon numarası düzeltme ve WhatsApp bağlantısı (saf Dart).
///
/// Rehberden ya da elle gelen numara ("0532 123 45 67", "+90 (532)
/// 123-4567", "5321234567") uluslararası biçime ("905321234567") çevrilir.
/// Başında + ya da 00 olan yabancı numaralar olduğu gibi kalır.
class PhoneNumber {
  const PhoneNumber._();

  /// Yalnız rakamlar, ülke koduyla; geçersizse null.
  static String? normalize(String? raw) {
    if (raw == null) return null;
    final trimmed = raw.trim();
    var digits = trimmed.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return null;
    final international = trimmed.startsWith('+') || digits.startsWith('00');
    if (digits.startsWith('00')) digits = digits.substring(2);
    if (!international) {
      if (digits.length == 11 && digits.startsWith('0')) {
        digits = '90${digits.substring(1)}';
      } else if (digits.length == 10) {
        digits = '90$digits';
      }
    }
    if (digits.startsWith('90') && digits.length != 12) return null;
    if (digits.length < 8 || digits.length > 15) return null;
    return digits;
  }

  /// Görünüm: "0532 123 45 67" (Türkiye), diğerleri "+44…".
  static String display(String raw) {
    final n = normalize(raw);
    if (n == null) return raw.trim();
    if (n.startsWith('90') && n.length == 12) {
      final d = n.substring(2);
      return '0${d.substring(0, 3)} ${d.substring(3, 6)} '
          '${d.substring(6, 8)} ${d.substring(8)}';
    }
    return '+$n';
  }

  // Boşluk "+" değil "%20" olmalı: WhatsApp "+"yı olduğu gibi yazar.
  static String _encode(String text) => Uri.encodeComponent(text);

  /// WhatsApp uygulamasını kişiyle ve hazır mesajla açan bağlantı.
  static Uri whatsApp(String number, String text) =>
      Uri.parse('whatsapp://send?phone=$number&text=${_encode(text)}');

  /// WhatsApp yüklü değilse tarayıcıda açılan yedek bağlantı.
  static Uri whatsAppWeb(String number, String text) =>
      Uri.parse('https://wa.me/$number?text=${_encode(text)}');
}
