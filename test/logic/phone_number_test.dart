import 'package:flutter_test/flutter_test.dart';
import 'package:nobet_listesi/logic/phone_number.dart';

void main() {
  test('Türkiye numaraları uluslararası biçime', () {
    for (final raw in [
      '0532 123 45 67',
      '+90 (532) 123-4567',
      '5321234567',
      '0090 532 123 45 67',
      '90 532 123 4567',
    ]) {
      expect(PhoneNumber.normalize(raw), '905321234567', reason: raw);
    }
  });

  test('yabancı numara korunur; geçersizler null', () {
    expect(PhoneNumber.normalize('+44 7700 900123'), '447700900123');
    expect(PhoneNumber.normalize('0532 123'), isNull);
    expect(PhoneNumber.normalize('abc'), isNull);
    expect(PhoneNumber.normalize(null), isNull);
  });

  test('görünüm', () {
    expect(PhoneNumber.display('+905321234567'), '0532 123 45 67');
    expect(PhoneNumber.display('+44 7700 900123'), '+447700900123');
    expect(PhoneNumber.display('12'), '12');
  });

  test('WhatsApp bağlantıları metni kodlar', () {
    final uri = PhoneNumber.whatsApp('905321234567', 'Merhaba, 5 Kasım & 7');
    expect(uri.scheme, 'whatsapp');
    expect(uri.queryParameters['phone'], '905321234567');
    expect(uri.queryParameters['text'], 'Merhaba, 5 Kasım & 7');
    expect(
      PhoneNumber.whatsAppWeb('905321234567', 'a b').toString(),
      'https://wa.me/905321234567?text=a%20b',
    );
  });
}
