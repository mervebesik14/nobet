import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

/// Okunamayan ya da Excel olmayan dosya.
class XlsxFormatException implements Exception {
  const XlsxFormatException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Excel (.xlsx) dosyasından bir sayfanın hücre değerlerini okur (saf Dart).
/// Excel, LibreOffice, Numbers ve Google E-Tablolar'ın kaydettiği dosyalar:
/// ortak metinler (sharedStrings), satır içi metinler ve sayılar. Biçimler
/// ve formüller okunmaz (formülün son hesaplanan değeri okunur).
class XlsxReader {
  const XlsxReader._();

  static const _relsNs =
      'http://schemas.openxmlformats.org/officeDocument/2006/relationships';

  /// [preferredSheet] adlı sayfa varsa o, yoksa ilk sayfa: satır → sütun →
  /// değer (metin `String`, sayı `num`, boş `null`). Satır ve sütunlar
  /// 0'dan başlar; boş satırlar boş liste olarak yer alır.
  static List<List<Object?>> readSheet(
    List<int> bytes, {
    String? preferredSheet,
  }) {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } on Object {
      throw const XlsxFormatException('Dosya bir Excel (.xlsx) dosyası değil.');
    }
    String? text(String path) {
      final file = archive.findFile(path);
      return file == null
          ? null
          : utf8.decode(file.content, allowMalformed: true);
    }

    XmlDocument parse(String path) {
      final content = text(path);
      if (content == null) {
        throw const XlsxFormatException(
          'Dosya bir Excel (.xlsx) dosyası değil.',
        );
      }
      try {
        return XmlDocument.parse(content);
      } on XmlException {
        throw const XlsxFormatException('Excel dosyası bozuk.');
      }
    }

    final workbook = parse('xl/workbook.xml');
    final sheets = workbook.findAllElements('sheet').toList();
    if (sheets.isEmpty) {
      throw const XlsxFormatException('Excel dosyasında sayfa yok.');
    }
    final sheet = sheets.firstWhere(
      (s) => s.getAttribute('name') == preferredSheet,
      orElse: () => sheets.first,
    );
    final relId =
        sheet.getAttribute('id', namespaceUri: _relsNs) ??
        sheet.getAttribute('r:id');

    // Sayfa dosyasının yolu: workbook.xml.rels içindeki hedef.
    var sheetPath = 'xl/worksheets/sheet${sheets.indexOf(sheet) + 1}.xml';
    final relsText = text('xl/_rels/workbook.xml.rels');
    if (relId != null && relsText != null) {
      final rels = XmlDocument.parse(relsText);
      for (final r in rels.findAllElements('Relationship')) {
        if (r.getAttribute('Id') != relId) continue;
        final target = r.getAttribute('Target')!;
        sheetPath = target.startsWith('/')
            ? target.substring(1)
            : 'xl/${target.replaceFirst(RegExp(r'^\./'), '')}';
      }
    }

    final shared = <String>[];
    if (text('xl/sharedStrings.xml') case final s?) {
      for (final si in XmlDocument.parse(s).findAllElements('si')) {
        // Biçimli metin parçalara bölünür (<r><t>); hepsi birleştirilir.
        shared.add(si.findAllElements('t').map((t) => t.innerText).join());
      }
    }

    final rows = <List<Object?>>[];
    for (final row in parse(sheetPath).findAllElements('row')) {
      final rowIndex =
          (int.tryParse(row.getAttribute('r') ?? '') ?? rows.length + 1) - 1;
      while (rows.length <= rowIndex) {
        rows.add([]);
      }
      final cells = rows[rowIndex];
      for (final c in row.findElements('c')) {
        final ref = c.getAttribute('r');
        final col = ref == null ? cells.length : columnIndex(ref);
        while (cells.length <= col) {
          cells.add(null);
        }
        cells[col] = _value(c, shared);
      }
    }
    return rows;
  }

  static Object? _value(XmlElement c, List<String> shared) {
    final type = c.getAttribute('t');
    final v = c.getElement('v')?.innerText;
    switch (type) {
      case 's':
        final i = int.tryParse(v ?? '');
        return i == null || i >= shared.length ? null : shared[i];
      case 'inlineStr':
        return c.findAllElements('t').map((t) => t.innerText).join();
      case 'str' || 'e':
        return v;
      case 'b':
        return v == '1' ? 'DOĞRU' : 'YANLIŞ';
      default:
        if (v == null || v.isEmpty) return null;
        final n = num.tryParse(v);
        if (n == null) return v;
        return n == n.roundToDouble() ? n.round() : n;
    }
  }

  /// "B12" → 1 (A = 0).
  static int columnIndex(String ref) {
    var n = 0;
    for (final ch in ref.toUpperCase().codeUnits) {
      if (ch < 65 || ch > 90) break;
      n = n * 26 + (ch - 64);
    }
    return n - 1;
  }
}
