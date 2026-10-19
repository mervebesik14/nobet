import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nobet_listesi/logic/xlsx_writer.dart';

void main() {
  Map<String, String> unzip(List<int> bytes) => {
    for (final f in ZipDecoder().decodeBytes(bytes))
      f.name: utf8.decode(f.content),
  };

  group('XlsxWriter', () {
    test('sütun adları', () {
      expect(XlsxWriter.columnName(0), 'A');
      expect(XlsxWriter.columnName(25), 'Z');
      expect(XlsxWriter.columnName(26), 'AA');
      expect(XlsxWriter.columnName(31), 'AF');
      expect(XlsxWriter.columnName(701), 'ZZ');
      expect(XlsxWriter.columnName(702), 'AAA');
    });

    test('dosya yapısı, metin, sayı ve biçimler', () {
      final files = unzip(
        XlsxWriter.build([
          const XlsxSheet(
            'Liste: Ekim/2026',
            rows: [
              [
                XlsxCell('Ayşe & <Işık>', style: XlsxStyle(bold: true)),
                XlsxCell(24),
                XlsxCell(7.5),
                XlsxCell.empty(style: XlsxStyle(fill: 0xE3ECEB)),
              ],
            ],
            columnWidths: {0: 24},
            freezeRows: 1,
            freezeColumns: 1,
            merges: ['A1:B1'],
            printLandscape: true,
          ),
          const XlsxSheet('İkinci', rows: []),
        ]),
      );
      expect(
        files.keys,
        containsAll([
          '[Content_Types].xml',
          '_rels/.rels',
          'xl/workbook.xml',
          'xl/_rels/workbook.xml.rels',
          'xl/styles.xml',
          'xl/worksheets/sheet1.xml',
          'xl/worksheets/sheet2.xml',
        ]),
      );
      final sheet = files['xl/worksheets/sheet1.xml']!;
      expect(
        sheet,
        contains('<t xml:space="preserve">Ayşe &amp; &lt;Işık&gt;</t>'),
      );
      expect(sheet, contains('<c r="B1" s="2"><v>24</v></c>'));
      expect(sheet, contains('<v>7.5</v>'));
      expect(sheet, contains('<c r="D1" s="3"/>'));
      expect(sheet, contains('xSplit="1" ySplit="1" topLeftCell="B2"'));
      expect(sheet, contains('<col min="1" max="1" width="24.0"'));
      expect(sheet, contains('<mergeCell ref="A1:B1"/>'));
      expect(sheet, contains('<pageSetUpPr fitToPage="1"/>'));
      expect(sheet, contains('orientation="landscape" fitToWidth="1"'));
      // Sayfa adında Excel'in kabul etmediği karakterler yok.
      expect(files['xl/workbook.xml'], contains('name="Liste  Ekim 2026"'));
      expect(files['xl/workbook.xml'], contains('name="İkinci"'));
      // Varsayılan + 3 biçim; dolgu rengi tanımlı.
      expect(files['xl/styles.xml'], contains('<cellXfs count="4">'));
      expect(files['xl/styles.xml'], contains('rgb="FFE3ECEB"'));
    });
  });
}
