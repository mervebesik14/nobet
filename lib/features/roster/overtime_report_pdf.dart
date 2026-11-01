import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../logic/roster_summary.dart';
import '../../logic/turkish_collation.dart';
import '../../logic/turkish_dates.dart';
import '../../models/models.dart';
import '../settings/report_info.dart';

const _primary = PdfColor.fromInt(0xFF0F7A61);
const _tint = PdfColor.fromInt(0xFFE6F2EE);
const _line = PdfColor.fromInt(0xFFB0BEC5);
const _muted = PdfColor.fromInt(0xFF607D8B);

/// İdareye verilecek aylık fazla çalışma çizelgesi (A4 dikey): kurum ve
/// birim başlığı, kişi başı nöbet / hafta sonu / resmi tatil nöbeti,
/// çalışılan, gereken ve fazla saat, toplam satırı ve imza alanları.
Future<Uint8List> buildOvertimeReportPdf({
  required int year,
  required int month,
  required RosterSummary summary,
  required ReportInfo info,
  required int shiftHours,
  required pw.Font font,
  required pw.Font boldFont,
  DateTime? createdAt,
}) async {
  final monthLabel = '${turkishMonthNames[month - 1]} $year';
  final doc = pw.Document(
    title: '$monthLabel Fazla Çalışma Çizelgesi',
    theme: pw.ThemeData.withFont(base: font, bold: boldFont),
  );
  final date = DateFormat(
    'd MMMM y',
    'tr_TR',
  ).format(createdAt ?? DateTime.now());
  String h(num v) => NumberFormat('#,##0.#', 'tr_TR').format(v);
  final rows = summary.people;
  final total = (
    shifts: rows.fold(0, (s, r) => s + r.shifts),
    weekend: rows.fold(0, (s, r) => s + r.weekendShifts),
    holiday: rows.fold(
      0,
      (s, r) => s + r.nationalHolidayShifts + r.religiousHolidayShifts,
    ),
    worked: rows.fold(0.0, (s, r) => s + r.workedHours),
    overtime: rows.fold(0.0, (s, r) => s + r.overtimeHours),
  );

  const headStyle = pw.TextStyle(fontSize: 8.5, color: PdfColors.white);
  pw.Widget cell(
    String text, {
    bool bold = false,
    pw.Alignment align = pw.Alignment.center,
  }) => pw.Container(
    alignment: align,
    padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 5),
    child: pw.Text(
      text,
      style: pw.TextStyle(
        fontSize: 9,
        fontWeight: bold ? pw.FontWeight.bold : null,
      ),
    ),
  );
  pw.Widget head(String text) => pw.Container(
    alignment: pw.Alignment.center,
    padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 5),
    child: pw.Text(text, style: headStyle, textAlign: pw.TextAlign.center),
  );

  pw.Widget signature(String label, String name, String title) => pw.Expanded(
    child: pw.Column(
      children: [
        pw.Text(
          label,
          style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 4),
        pw.Text(date, style: const pw.TextStyle(fontSize: 9)),
        pw.SizedBox(height: 36),
        pw.Container(
          width: 150,
          decoration: const pw.BoxDecoration(
            border: pw.Border(top: pw.BorderSide(color: _line)),
          ),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          name.isEmpty ? 'Ad Soyad' : name,
          style: pw.TextStyle(
            fontSize: 10,
            color: name.isEmpty ? _muted : null,
          ),
        ),
        pw.Text(
          title.isEmpty ? 'Unvan · İmza' : '$title · İmza',
          style: const pw.TextStyle(fontSize: 9, color: _muted),
        ),
      ],
    ),
  );

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4.copyWith(
        marginLeft: 1.5 * PdfPageFormat.cm,
        marginRight: 1.5 * PdfPageFormat.cm,
        marginTop: 1.3 * PdfPageFormat.cm,
        marginBottom: 1.3 * PdfPageFormat.cm,
      ),
      footer: (context) => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text(
          'Sayfa ${context.pageNumber} / ${context.pagesCount}',
          style: const pw.TextStyle(fontSize: 8, color: _muted),
        ),
      ),
      build: (_) => [
        pw.Center(
          child: pw.Column(
            children: [
              if (info.institution.isNotEmpty)
                pw.Text(
                  turkishUpperCase(info.institution),
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(
                    fontSize: 12,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              if (info.unit.isNotEmpty)
                pw.Text(
                  info.unit,
                  textAlign: pw.TextAlign.center,
                  style: const pw.TextStyle(fontSize: 11),
                ),
              pw.SizedBox(height: 8),
              pw.Text(
                '${turkishUpperCase(monthLabel)} FAZLA ÇALIŞMA (NÖBET) '
                'ÇİZELGESİ',
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(
                  fontSize: 12,
                  fontWeight: pw.FontWeight.bold,
                  color: _primary,
                ),
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 10),
        pw.Text(
          'Nöbet süresi $shiftHours saat. Ayın gereken çalışma süresi '
          '${h(summary.requiredHours)} saat. Fazla çalışma = çalışılan − '
          'gereken (eksiyse 0).',
          style: const pw.TextStyle(fontSize: 9, color: _muted),
        ),
        pw.SizedBox(height: 8),
        pw.Table(
          border: pw.TableBorder.all(color: _line, width: 0.5),
          columnWidths: const {
            0: pw.FixedColumnWidth(22),
            1: pw.FlexColumnWidth(3.2),
            2: pw.FlexColumnWidth(2.1),
          },
          children: [
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: _primary),
              children: [
                head('Sıra'),
                head('Ad Soyad'),
                head('Unvan'),
                head('Nöbet'),
                head('Hafta sonu'),
                head('Resmi tatil'),
                head('Çalışılan saat'),
                head('Gereken saat'),
                head('Fazla çalışma (saat)'),
              ],
            ),
            for (var i = 0; i < rows.length; i++)
              pw.TableRow(
                decoration: i.isOdd
                    ? const pw.BoxDecoration(color: _tint)
                    : null,
                children: [
                  cell('${i + 1}'),
                  cell(rows[i].name, align: pw.Alignment.centerLeft),
                  cell(
                    rows[i].isChargeNurse
                        ? 'Sorumlu Hemşire'
                        : rows[i].role == Role.nurse
                        ? 'Hemşire'
                        : 'Radyoloji Tek.',
                    align: pw.Alignment.centerLeft,
                  ),
                  cell('${rows[i].shifts}'),
                  cell('${rows[i].weekendShifts}'),
                  cell(
                    '${rows[i].nationalHolidayShifts + rows[i].religiousHolidayShifts}',
                  ),
                  cell(h(rows[i].workedHours)),
                  cell(h(rows[i].requiredHours)),
                  cell(h(rows[i].overtimeHours), bold: true),
                ],
              ),
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: _tint),
              children: [
                cell(''),
                cell('Toplam', bold: true, align: pw.Alignment.centerLeft),
                cell(''),
                cell('${total.shifts}', bold: true),
                cell('${total.weekend}', bold: true),
                cell('${total.holiday}', bold: true),
                cell(h(total.worked), bold: true),
                cell(''),
                cell(h(total.overtime), bold: true),
              ],
            ),
          ],
        ),
        pw.SizedBox(height: 40),
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
