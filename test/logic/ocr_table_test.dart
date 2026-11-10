import 'package:flutter_test/flutter_test.dart';
import 'package:nobet_listesi/logic/ocr_table.dart';
import 'package:nobet_listesi/logic/roster_import.dart';
import 'package:nobet_listesi/models/models.dart';

void main() {
  const people = [
    Person(id: 'a', name: 'Ayşe Yılmaz', role: Role.nurse),
    Person(id: 'b', name: 'Banu Kaya', role: Role.nurse),
    Person(id: 't', name: 'Tarık Şen', role: Role.radiologyTech),
  ];
  // Gün d'nin sütun merkezi; satırlar 0.1 aralıklı.
  double x(int d) => 0.2 + d * 0.025;
  OcrBox box(String text, double cx, double y, {double w = 0.02}) =>
      (text: text, x: cx - w / 2, y: y, w: w, h: 0.02);

  final boxes = <OcrBox>[
    // Başlık: 1–30, 9 ve 17 okunamamış.
    for (var d = 1; d <= 30; d++)
      if (d != 9 && d != 17) box('$d', x(d), 0.10 + (d.isEven ? 0.003 : 0)),
    // Ayşe (Türkçe harfsiz okunmuş): 3, 12 nöbet; 20 yıllık izin.
    box('Ayse Yilmaz', 0.08, 0.20, w: 0.12),
    box('24', x(3), 0.201),
    box('24', x(12), 0.199),
    box('Y.İ.', x(20), 0.20),
    // Banu: 5 ve 6 tek kutuda birleşmiş "24 24".
    box('Banu Kaya', 0.08, 0.30, w: 0.10),
    (text: '24 24', x: x(5) - 0.01, y: 0.30, w: x(6) - x(5) + 0.02, h: 0.02),
    // Tarık: 16A.
    box('Tank Sen', 0.08, 0.40, w: 0.10),
    box('16A', x(9), 0.40),
  ];

  test('ızgara: gün sütunları, birleşik kutu, ad eşleştirme', () {
    final rows = OcrTable.toRows(boxes, people: people, daysInMonth: 30);
    expect(rows.first.length, 31);
    expect(rows.first[1], 1);
    final ayse = rows.firstWhere((r) => r.first == 'Ayşe Yılmaz');
    expect(ayse[3], '24');
    expect(ayse[12], '24');
    expect(ayse[20], 'Y.İ.');
    final banu = rows.firstWhere((r) => r.first == 'Banu Kaya');
    expect(banu[5], '24');
    expect(banu[6], '24');
    expect(rows.any((r) => r.first == 'Tarık Şen'), isTrue);
  });

  test('içe aktarmayla birlikte', () {
    final r = RosterImport.fromRows(
      rows: OcrTable.toRows(boxes, people: people, daysInMonth: 30),
      year: 2026,
      month: 11,
      people: people,
    );
    expect(r.assignments[3]!.nurseIds, ['a']);
    expect(r.assignments[5]!.nurseIds, ['b']);
    expect(r.assignments[9]!.techId, 't');
    expect(r.assignments[9]!.shift16aIds, ['t']);
    expect(r.leaves[LeaveType.annual]!['a'], [20]);
  });

  test('ad eşleştirme sınırları', () {
    expect(OcrTable.matchName('AYSE YILMAZ', people), 'Ayşe Yılmaz');
    expect(OcrTable.matchName('Banu', people), 'Banu Kaya');
    expect(OcrTable.matchName('Zeynep Ok', people), isNull);
    expect(OcrTable.toRows(const []), isEmpty);
  });
}
