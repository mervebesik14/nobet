import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nobet_listesi/logic/xlsx_reader.dart';
import 'package:nobet_listesi/logic/xlsx_writer.dart';

/// Excel'in kaydettiği biçimde (ortak metinler, `r:id`, sayfa yolu
/// ilişkiden) küçük bir dosya.
List<int> excelStyleFile() {
  final archive = Archive();
  void add(String path, String content) {
    final bytes = utf8.encode(content);
    archive.addFile(ArchiveFile(path, bytes.length, bytes));
  }

  add(
    'xl/workbook.xml',
    '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
        '<sheets><sheet name="Notlar" sheetId="1" r:id="rId1"/>'
        '<sheet name="Nöbet Listesi" sheetId="2" r:id="rId7"/></sheets></workbook>',
  );
  add(
    'xl/_rels/workbook.xml.rels',
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="x" Target="worksheets/sheet1.xml"/>'
        '<Relationship Id="rId7" Type="x" Target="/xl/worksheets/liste.xml"/>'
        '</Relationships>',
  );
  add(
    'xl/sharedStrings.xml',
    '<sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
        '<si><t>Ad Soyad</t></si>'
        '<si><r><t>Ayşe </t></r><r><rPr><b/></rPr><t>Işık</t></r></si>'
        '<si><t>16B</t></si>'
        '</sst>',
  );
  add(
    'xl/worksheets/sheet1.xml',
    '<worksheet><sheetData><row r="1"><c r="A1" t="inlineStr">'
        '<is><t>yanlış sayfa</t></is></c></row></sheetData></worksheet>',
  );
  add(
    'xl/worksheets/liste.xml',
    '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
        '<sheetData>'
        '<row r="2"><c r="A2" t="s"><v>0</v></c><c r="C2"><v>24</v></c></row>'
        '<row r="3"><c r="A3" t="s"><v>1</v></c><c r="B3"><v>7.5</v></c>'
        '<c r="C3" t="s"><v>2</v></c>'
        '<c r="D3" t="str"><f>A1</f><v>hesap</v></c></row>'
        '</sheetData></worksheet>',
  );
  return ZipEncoder().encode(archive);
}

void main() {
  test('sütun harfi', () {
    expect(XlsxReader.columnIndex('A1'), 0);
    expect(XlsxReader.columnIndex('AF12'), 31);
    expect(XlsxReader.columnIndex('aa3'), 26);
  });

  test('kendi yazdığımız dosya geri okunur', () {
    final bytes = XlsxWriter.build([
      const XlsxSheet(
        'Liste',
        rows: [
          [XlsxCell('Başlık')],
          [XlsxCell('Ad Soyad'), XlsxCell('1\nPer'), XlsxCell(24)],
          [],
          [XlsxCell.empty(), XlsxCell('16B')],
        ],
      ),
    ]);
    expect(XlsxReader.readSheet(bytes), [
      ['Başlık'],
      ['Ad Soyad', '1\nPer', 24],
      [],
      [null, '16B'],
    ]);
  });

  test('Excel biçimi: ortak metinler, tercih edilen sayfa, formül sonucu', () {
    final rows = XlsxReader.readSheet(
      excelStyleFile(),
      preferredSheet: 'Nöbet Listesi',
    );
    expect(rows, [
      [],
      ['Ad Soyad', null, 24],
      ['Ayşe Işık', 7.5, '16B', 'hesap'],
    ]);
    // Tercih edilen sayfa yoksa ilk sayfa.
    expect(XlsxReader.readSheet(excelStyleFile()), [
      ['yanlış sayfa'],
    ]);
  });

  test('Excel olmayan dosya anlaşılır hata verir', () {
    expect(
      () => XlsxReader.readSheet(utf8.encode('merhaba')),
      throwsA(isA<XlsxFormatException>()),
    );
  });
}
