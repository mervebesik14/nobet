import 'package:flutter_test/flutter_test.dart';
import 'package:nobet_listesi/logic/ocr_table.dart';
import 'package:nobet_listesi/logic/ocr_text.dart';
import 'package:nobet_listesi/logic/request_parser.dart';
import 'package:nobet_listesi/models/models.dart';

OcrBox box(String t, double x, double y) =>
    (text: t, x: x, y: y, w: 0.2, h: 0.02);

void main() {
  test('satırlar birleşir, saat ve gürültü atılır, kendi mesajımız atılır', () {
    final message = RequestParser.message(year: 2026, month: 12);
    final lines = OcrText.lines([
      box('09:41', 0.05, 0.01),
      box('Emre Dinç', 0.3, 0.05),
      box('çevrimiçi', 0.3, 0.075),
      box('Bugün', 0.45, 0.12),
      // Bizim gönderdiğimiz mesajın bir satırı.
      box('İzin varsa: izin 20-24', 0.4, 0.2),
      box('3, 7, 12-14', 0.05, 0.3),
      box('olmaz', 0.3, 0.305),
      box('14:03', 0.6, 0.31),
      box('izin 20-22', 0.05, 0.35),
    ], ignore: message);
    expect(lines, ['Emre Dinç', '3, 7, 12-14 olmaz', 'izin 20-22']);

    // Okuyucu başlıktaki adı gönderen sayar.
    final r = RequestParser.parse(
      text: lines.join('\n'),
      people: const [Person(id: 'e', name: 'Emre Dinç', role: Role.nurse)],
      year: 2026,
      month: 12,
    );
    expect(r.requests['e']!.unavailable, {3, 7, 12, 13, 14});
    expect(r.requests['e']!.leaves[LeaveType.annual], {20, 21, 22});
  });
}
