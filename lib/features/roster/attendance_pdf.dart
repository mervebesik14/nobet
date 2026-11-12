import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../logic/attendance_sheet.dart';
import '../../logic/turkish_collation.dart';
import '../../logic/turkish_dates.dart';
import '../settings/report_info.dart';

const _primary = PdfColor.fromInt(0xFF0F7A61);
const _closed = PdfColor.fromInt(0xFFCAE2DC);
const _off = PdfColor.fromInt(0xFFF2F2F2);
const _line = PdfColor.fromInt(0xFFB0BEC5);
const _muted = PdfColor.fromInt(0xFF607D8B);

const _weekdays = ['Pt', 'Sa', 'Ça', 'Pe', 'Cu', 'Ct', 'Pz'];

/// Puantaj cetveli (A4 yatay): kişi × gün kodları, toplamlar, açıklama ve
/// imza alanları.
Future<Uint8List> buildAttendancePdf({
  required int year,
  required int month,
  required List<AttendanceRow> rows,
  required Set<int> closedDays,
  required ReportInfo info,
  required pw.Font font,
  required pw.Font boldFont,
  Iterable<String> customCodes = const [],
}) async {
  final monthLabel = '${turkishMonthNames[month - 1]} $year';
  final days = DateTime(year, month + 1, 0).day;
  final doc = pw.Document(
    title: '$monthLabel Puantaj Cetveli',
    theme: pw.ThemeData.withFont(base: font, bold: boldFont),
  );

  pw.Widget cell(
    String text, {
    PdfColor? fill,
    bool bold = false,
    double size = 6.5,
    pw.Alignment align = pw.Alignment.center,
  }) => pw.Container(
    alignment: align,
    color: fill,
    padding: const pw.EdgeInsets.symmetric(horizontal: 1, vertical: 3),
    child: pw.Text(
      text,
      textAlign: pw.TextAlign.center,
      style: pw.TextStyle(
        fontSize: size,
        fontWeight: bold ? pw.FontWeight.bold : null,
      ),
    ),
  );
  pw.Widget head(String text, {PdfColor? fill}) => pw.Container(
    alignment: pw.Alignment.center,
    color: fill ?? _primary,
    padding: const pw.EdgeInsets.symmetric(horizontal: 1, vertical: 3),
    child: pw.Text(
      text,
      textAlign: pw.TextAlign.center,
      style: pw.TextStyle(
        fontSize: 6.5,
        fontWeight: pw.FontWeight.bold,
        color: fill == null ? PdfColors.white : PdfColors.black,
      ),
    ),
  );

  pw.Widget signature(String label, String name, String title) => pw.Expanded(
    child: pw.Column(
      children: [
        pw.Text(
          label,
          style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 26),
        pw.Container(
          width: 140,
          decoration: const pw.BoxDecoration(
            border: pw.Border(top: pw.BorderSide(color: _line)),
          ),
        ),
        pw.SizedBox(height: 3),
        pw.Text(
          name.isEmpty ? 'Ad Soyad' : name,
          style: pw.TextStyle(fontSize: 9, color: name.isEmpty ? _muted : null),
        ),
        pw.Text(
          title.isEmpty ? 'Unvan · İmza' : '$title · İmza',
          style: const pw.TextStyle(fontSize: 8, color: _muted),
        ),
      ],
    ),
  );

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4.landscape.copyWith(
        marginLeft: 0.8 * PdfPageFormat.cm,
        marginRight: 0.8 * PdfPageFormat.cm,
        marginTop: 0.9 * PdfPageFormat.cm,
        marginBottom: 0.9 * PdfPageFormat.cm,
      ),
      footer: (context) => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text(
          'Sayfa ${context.pageNumber} / ${context.pagesCount}',
          style: const pw.TextStyle(fontSize: 7, color: _muted),
        ),
      ),
      build: (_) => [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  if (info.institution.isNotEmpty)
                    pw.Text(
                      turkishUpperCase(info.institution),
                      style: pw.TextStyle(
                        fontSize: 10,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  if (info.unit.isNotEmpty)
                    pw.Text(info.unit, style: const pw.TextStyle(fontSize: 9)),
                ],
              ),
            ),
            pw.Text(
              '${turkishUpperCase(monthLabel)} PUANTAJ CETVELİ',
              style: pw.TextStyle(
                fontSize: 12,
                fontWeight: pw.FontWeight.bold,
                color: _primary,
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 6),
        pw.Table(
          border: pw.TableBorder.all(color: _line, width: 0.4),
          // Zemin rengi hücrenin tamamını kaplasın.
          defaultVerticalAlignment: pw.TableCellVerticalAlignment.full,
          columnWidths: {
            0: const pw.FixedColumnWidth(14),
            1: const pw.FixedColumnWidth(78),
            2: const pw.FixedColumnWidth(48),
            for (var c = 3; c < 3 + days; c++) c: const pw.FlexColumnWidth(),
            for (var c = 3 + days; c < 7 + days; c++)
              c: const pw.FixedColumnWidth(20),
          },
          children: [
            pw.TableRow(
              repeat: true,
              children: [
                head('#'),
                head('Ad Soyad'),
                head('Unvan'),
                for (var d = 1; d <= days; d++)
                  head(
                    '$d\n${_weekdays[DateTime(year, month, d).weekday - 1]}',
                    fill: closedDays.contains(d) ? _closed : null,
                  ),
                head('Nöbet'),
                head('7A'),
                head(AttendanceSheet.offCode),
                head('İzin'),
              ],
            ),
            for (final (i, r) in rows.indexed)
              pw.TableRow(
                children: [
                  cell('${i + 1}'),
                  cell(r.name, align: pw.Alignment.centerLeft, size: 7),
                  cell(
                    r.title.replaceFirst('Teknikeri', 'Tek.'),
                    align: pw.Alignment.centerLeft,
                    size: 6,
                  ),
                  for (var d = 1; d <= days; d++)
                    cell(
                      r.codes[d - 1],
                      fill: closedDays.contains(d)
                          ? _closed
                          : r.codes[d - 1] == AttendanceSheet.offCode
                          ? _off
                          : null,
                      bold:
                          r.codes[d - 1].isNotEmpty &&
                          !r.codes[d - 1].endsWith('.'),
                      size: r.codes[d - 1].length > 3 ? 5 : 6.5,
                    ),
                  cell('${r.shifts}', bold: true),
                  cell('${r.dayShifts}'),
                  cell('${r.offDays}'),
                  cell('${r.leaveDays}'),
                ],
              ),
          ],
        ),
        pw.SizedBox(height: 6),
        pw.Wrap(
          spacing: 14,
          runSpacing: 2,
          children: [
            for (final l in AttendanceSheet.legend(customCodes: customCodes))
              pw.Text(l, style: const pw.TextStyle(fontSize: 7, color: _muted)),
          ],
        ),
        pw.SizedBox(height: 14),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            signature('Hazırlayan', info.preparedBy, info.preparedTitle),
            signature('Onaylayan', info.approvedBy, info.approvedTitle),
          ],
        ),
      ],
    ),
  );
  return doc.save();
}
