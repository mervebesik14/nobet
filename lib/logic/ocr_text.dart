import 'ocr_table.dart';
import 'turkish_collation.dart';

/// Ekran görüntüsündeki metin kutularını okunur satırlara çevirir (saf
/// Dart): aynı yükseklikteki kutular soldan sağa birleşir, satırlar
/// yukarıdan aşağı sıralanır. WhatsApp gürültüsü (saat, "Bugün", çift tik,
/// "yazıyor…", çevrimiçi) ve [ignore] metninin parçası olan satırlar (ör.
/// gönderdiğimiz istek mesajı) atılır.
class OcrText {
  const OcrText._();

  static final _time = RegExp(r'\b\d{1,2}[:.]\d{2}\b(\s*[✓✔√]+)?');
  static final _noise = RegExp(
    r'^(bugün|dün|today|yesterday|çevrimiçi|online|yazıyor\.*|'
    r'mesaj|message|son görülme.*|[✓✔√\s]+|\d{1,2}\s+[a-zçğıöşü]+\s+\d{4})$',
  );

  static List<String> lines(List<OcrBox> boxes, {String ignore = ''}) {
    final sorted = [...boxes]..sort((a, b) => a.y.compareTo(b.y));
    final rows = <List<OcrBox>>[];
    for (final b in sorted) {
      final mid = b.y + b.h / 2;
      final row = rows.where((r) {
        final f = r.first;
        return (f.y + f.h / 2 - mid).abs() < (f.h < b.h ? f.h : b.h) * 0.6;
      }).firstOrNull;
      if (row == null) {
        rows.add([b]);
      } else {
        row.add(b);
      }
    }
    final skip = _norm(ignore);
    final out = <String>[];
    for (final row in rows) {
      row.sort((a, b) => a.x.compareTo(b.x));
      final text = row
          .map((b) => b.text.trim())
          .join(' ')
          .replaceAll(_time, '')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      if (text.isEmpty) continue;
      final low = turkishLowerCase(text);
      if (_noise.hasMatch(low)) continue;
      final n = _norm(text);
      if (n.length >= 6 && skip.contains(n)) continue;
      out.add(text);
    }
    return out;
  }

  static String _norm(String s) =>
      normalizeName(s).replaceAll(RegExp(r'[^a-z0-9]'), '');
}
