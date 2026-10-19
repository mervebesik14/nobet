import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// Hücre hizası.
enum XlsxAlign { left, center, right }

/// Hücre biçimi: kalın yazı, dolgu rengi (0xRRGGBB), hiza, kenarlık, kaydırma.
class XlsxStyle {
  const XlsxStyle({
    this.bold = false,
    this.fill,
    this.align,
    this.border = true,
    this.wrap = false,
  });

  final bool bold;
  final int? fill;
  final XlsxAlign? align;
  final bool border;
  final bool wrap;

  XlsxStyle copyWith({bool? bold, int? fill, XlsxAlign? align}) => XlsxStyle(
    bold: bold ?? this.bold,
    fill: fill ?? this.fill,
    align: align ?? this.align,
    border: border,
    wrap: wrap,
  );

  @override
  bool operator ==(Object other) =>
      other is XlsxStyle &&
      other.bold == bold &&
      other.fill == fill &&
      other.align == align &&
      other.border == border &&
      other.wrap == wrap;

  @override
  int get hashCode => Object.hash(bold, fill, align, border, wrap);
}

/// Bir hücre: metin, sayı ya da boş (null).
class XlsxCell {
  const XlsxCell(this.value, {this.style = const XlsxStyle()});

  /// Biçimli boş hücre.
  const XlsxCell.empty({this.style = const XlsxStyle()}) : value = null;

  final Object? value;
  final XlsxStyle style;
}

/// Bir çalışma sayfası.
class XlsxSheet {
  const XlsxSheet(
    this.name, {
    required this.rows,
    this.columnWidths = const {},
    this.rowHeights = const {},
    this.freezeRows = 0,
    this.freezeColumns = 0,
    this.merges = const [],
    this.printLandscape = false,
  });

  /// Sayfa adı (en fazla 31 karakter).
  final String name;

  final List<List<XlsxCell>> rows;

  /// Sütun (0'dan) → genişlik (karakter).
  final Map<int, double> columnWidths;

  /// Satır (0'dan) → yükseklik (punto).
  final Map<int, double> rowHeights;

  /// Kaydırırken sabit kalan üst satır ve sol sütun sayısı.
  final int freezeRows;
  final int freezeColumns;

  /// Birleştirilen alanlar, ör. "A1:F1".
  final List<String> merges;

  /// Yazdırırken yatay sayfa ve bir sayfa genişliğine sığdır.
  final bool printLandscape;
}

/// Excel (.xlsx) dosyası üretir (saf Dart). Metinler satır içi yazılır;
/// yalnızca nöbet listesinin gerektirdiği biçimler desteklenir.
class XlsxWriter {
  const XlsxWriter._();

  static const mimeType =
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

  /// 0 → A, 25 → Z, 26 → AA.
  static String columnName(int index) {
    var n = index + 1;
    final buf = StringBuffer();
    while (n > 0) {
      final r = (n - 1) % 26;
      buf.write(String.fromCharCode(65 + r));
      n = (n - 1) ~/ 26;
    }
    return buf.toString().split('').reversed.join();
  }

  static String _esc(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');

  static String _num(num v) {
    if (v is int || v == v.roundToDouble()) return v.round().toString();
    return v.toString();
  }

  static Uint8List build(List<XlsxSheet> sheets) {
    final styles = <XlsxStyle>[const XlsxStyle(border: false)];
    int styleIndex(XlsxStyle s) {
      final i = styles.indexOf(s);
      if (i >= 0) return i;
      styles.add(s);
      return styles.length - 1;
    }

    final sheetXml = [for (final sheet in sheets) _sheet(sheet, styleIndex)];

    final archive = Archive();
    void add(String path, String content) {
      final bytes = utf8.encode(content);
      archive.addFile(ArchiveFile(path, bytes.length, bytes));
    }

    add('[Content_Types].xml', _contentTypes(sheets.length));
    add('_rels/.rels', _rootRels);
    add('xl/workbook.xml', _workbook(sheets));
    add('xl/_rels/workbook.xml.rels', _workbookRels(sheets.length));
    add('xl/styles.xml', _styles(styles));
    for (var i = 0; i < sheetXml.length; i++) {
      add('xl/worksheets/sheet${i + 1}.xml', sheetXml[i]);
    }
    return Uint8List.fromList(ZipEncoder().encode(archive));
  }

  static String _sheet(XlsxSheet sheet, int Function(XlsxStyle) styleIndex) {
    final b = StringBuffer(
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">',
    );
    if (sheet.printLandscape) {
      b.write('<sheetPr><pageSetUpPr fitToPage="1"/></sheetPr>');
    }
    if (sheet.freezeRows > 0 || sheet.freezeColumns > 0) {
      final topLeft =
          '${columnName(sheet.freezeColumns)}${sheet.freezeRows + 1}';
      b.write(
        '<sheetViews><sheetView workbookViewId="0"><pane'
        '${sheet.freezeColumns > 0 ? ' xSplit="${sheet.freezeColumns}"' : ''}'
        '${sheet.freezeRows > 0 ? ' ySplit="${sheet.freezeRows}"' : ''}'
        ' topLeftCell="$topLeft" activePane="bottomRight" state="frozen"/>'
        '</sheetView></sheetViews>',
      );
    }
    if (sheet.columnWidths.isNotEmpty) {
      b.write('<cols>');
      for (final e
          in (sheet.columnWidths.entries.toList()
            ..sort((a, b) => a.key.compareTo(b.key)))) {
        b.write(
          '<col min="${e.key + 1}" max="${e.key + 1}" '
          'width="${e.value}" customWidth="1"/>',
        );
      }
      b.write('</cols>');
    }
    b.write('<sheetData>');
    for (var r = 0; r < sheet.rows.length; r++) {
      final height = sheet.rowHeights[r];
      b.write(
        '<row r="${r + 1}"'
        '${height == null ? '' : ' ht="$height" customHeight="1"'}>',
      );
      final row = sheet.rows[r];
      for (var c = 0; c < row.length; c++) {
        final cell = row[c];
        final ref = '${columnName(c)}${r + 1}';
        final s = styleIndex(cell.style);
        switch (cell.value) {
          case null:
            b.write('<c r="$ref" s="$s"/>');
          case final num v:
            b.write('<c r="$ref" s="$s"><v>${_num(v)}</v></c>');
          case final v:
            b.write(
              '<c r="$ref" s="$s" t="inlineStr"><is>'
              '<t xml:space="preserve">${_esc('$v')}</t></is></c>',
            );
        }
      }
      b.write('</row>');
    }
    b.write('</sheetData>');
    if (sheet.merges.isNotEmpty) {
      b.write('<mergeCells count="${sheet.merges.length}">');
      for (final m in sheet.merges) {
        b.write('<mergeCell ref="$m"/>');
      }
      b.write('</mergeCells>');
    }
    if (sheet.printLandscape) {
      b.write(
        '<pageMargins left="0.4" right="0.4" top="0.5" bottom="0.5" '
        'header="0.3" footer="0.3"/>'
        '<pageSetup paperSize="9" orientation="landscape" fitToWidth="1" '
        'fitToHeight="0"/>',
      );
    }
    b.write('</worksheet>');
    return b.toString();
  }

  static String _styles(List<XlsxStyle> styles) {
    final fills = <int>{
      for (final s in styles)
        if (s.fill != null) s.fill!,
    }.toList();
    String hex(int rgb) =>
        'FF${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
    final b = StringBuffer(
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
      '<fonts count="2">'
      '<font><sz val="10"/><name val="Calibri"/></font>'
      '<font><b/><sz val="10"/><name val="Calibri"/></font>'
      '</fonts>'
      '<fills count="${fills.length + 2}">'
      '<fill><patternFill patternType="none"/></fill>'
      '<fill><patternFill patternType="gray125"/></fill>',
    );
    for (final f in fills) {
      b.write(
        '<fill><patternFill patternType="solid">'
        '<fgColor rgb="${hex(f)}"/><bgColor indexed="64"/>'
        '</patternFill></fill>',
      );
    }
    b.write(
      '</fills>'
      '<borders count="2">'
      '<border><left/><right/><top/><bottom/><diagonal/></border>'
      '<border>'
      '<left style="thin"><color rgb="FF9E9E9E"/></left>'
      '<right style="thin"><color rgb="FF9E9E9E"/></right>'
      '<top style="thin"><color rgb="FF9E9E9E"/></top>'
      '<bottom style="thin"><color rgb="FF9E9E9E"/></bottom>'
      '<diagonal/></border>'
      '</borders>'
      '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" '
      'borderId="0"/></cellStyleXfs>'
      '<cellXfs count="${styles.length}">',
    );
    for (final s in styles) {
      final fillId = s.fill == null ? 0 : fills.indexOf(s.fill!) + 2;
      final align = s.align == null && !s.wrap
          ? ''
          : '<alignment'
                '${s.align == null ? '' : ' horizontal="${s.align!.name}"'}'
                ' vertical="center"'
                '${s.wrap ? ' wrapText="1"' : ''}/>';
      b.write(
        '<xf numFmtId="0" fontId="${s.bold ? 1 : 0}" fillId="$fillId" '
        'borderId="${s.border ? 1 : 0}" xfId="0"'
        '${s.fill != null ? ' applyFill="1"' : ''}'
        '${s.border ? ' applyBorder="1"' : ''}'
        '${s.bold ? ' applyFont="1"' : ''}'
        '${align.isEmpty ? '/>' : ' applyAlignment="1">$align</xf>'}',
      );
    }
    b.write(
      '</cellXfs>'
      '<cellStyles count="1"><cellStyle name="Normal" xfId="0" '
      'builtinId="0"/></cellStyles>'
      '</styleSheet>',
    );
    return b.toString();
  }

  static String _contentTypes(int sheets) =>
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
      '<Default Extension="rels" '
      'ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
      '<Default Extension="xml" ContentType="application/xml"/>'
      '<Override PartName="/xl/workbook.xml" '
      'ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
      '<Override PartName="/xl/styles.xml" '
      'ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'
      '${[for (var i = 1; i <= sheets; i++) '<Override PartName="/xl/worksheets/sheet$i.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'].join()}'
      '</Types>';

  static const _rootRels =
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rId1" '
      'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" '
      'Target="xl/workbook.xml"/>'
      '</Relationships>';

  /// Excel'in sayfa adında kabul etmediği karakterler çıkarılır.
  static String _sheetName(String name) {
    final clean = name.replaceAll(RegExp(r'[\[\]:*?/\\]'), ' ');
    return clean.length > 31 ? clean.substring(0, 31) : clean;
  }

  static String _workbook(List<XlsxSheet> sheets) =>
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
      'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
      '<sheets>'
      '${[for (var i = 0; i < sheets.length; i++) '<sheet name="${_esc(_sheetName(sheets[i].name))}" sheetId="${i + 1}" r:id="rId${i + 1}"/>'].join()}'
      '</sheets></workbook>';

  static String _workbookRels(int sheets) =>
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '${[for (var i = 1; i <= sheets; i++) '<Relationship Id="rId$i" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet$i.xml"/>'].join()}'
      '<Relationship Id="rId${sheets + 1}" '
      'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" '
      'Target="styles.xml"/>'
      '</Relationships>';
}
