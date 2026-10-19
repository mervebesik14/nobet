import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../logic/turkish_dates.dart';
import '../../logic/yearly_excel.dart';
import '../../logic/yearly_report.dart';
import '../../logic/yearly_summary.dart';

/// İstatistik sekmesinin PDF'i: yıllık kişi toplamları ve her ölçü için
/// aylara göre karşılaştırma (ortalamanın üstü kırmızı, altı mavi).
Future<Uint8List> buildStatisticsPdf({
  required int year,
  required YearlySummary summary,
  required pw.Font font,
  required pw.Font boldFont,
}) async {
  final number = NumberFormat('#,##0.#', 'tr_TR');
  String n(num v) => number.format(v);
  final border = pw.TableBorder.all(color: PdfColors.grey500, width: 0.4);
  final head = pw.TextStyle(font: boldFont, fontSize: 8);
  const body = pw.TextStyle(fontSize: 8);
  final months = summary.months;

  pw.Widget cell(String text, {PdfColor? color, pw.TextStyle? style}) =>
      pw.Container(
        color: color,
        alignment: pw.Alignment.center,
        padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 3),
        child: pw.Text(text, style: style ?? body),
      );

  pw.Widget nameCell(String text, {pw.TextStyle? style}) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 3),
    child: pw.Text(text, style: style ?? body, maxLines: 1),
  );

  pw.Widget comparison(YearlyMetric metric) => pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.SizedBox(height: 10),
      pw.Text(metric.label, style: pw.TextStyle(font: boldFont, fontSize: 10)),
      pw.SizedBox(height: 3),
      pw.Table(
        border: border,
        defaultVerticalAlignment: pw.TableCellVerticalAlignment.full,
        columnWidths: {
          0: const pw.FixedColumnWidth(110),
          for (var i = 1; i <= months.length + 1; i++)
            i: const pw.FlexColumnWidth(),
        },
        children: [
          pw.TableRow(
            repeat: true,
            decoration: const pw.BoxDecoration(color: PdfColors.grey200),
            children: [
              nameCell('Ad Soyad', style: head),
              for (final m in months)
                cell(turkishMonthNames[m - 1].substring(0, 3), style: head),
              cell('Toplam', style: head),
            ],
          ),
          for (final r in summary.rows)
            pw.TableRow(
              children: [
                nameCell(r.name),
                for (final m in months)
                  if (r.byMonth[m] case final t?)
                    cell(
                      n(metric.pick(t)),
                      color: switch (YearlyReport.tint(
                        summary.deviation(r, m, metric.pick),
                      )) {
                        final rgb? => PdfColor.fromInt(0xFF000000 | rgb),
                        null => null,
                      },
                    )
                  else
                    cell(''),
                cell(n(metric.pick(r.totals)), style: head),
              ],
            ),
        ],
      ),
    ],
  );

  final doc = pw.Document(
    title: '$year Nöbet İstatistiği',
    theme: pw.ThemeData.withFont(base: font, bold: boldFont),
  );
  doc.addPage(
    pw.MultiPage(
      pageFormat: const PdfPageFormat(
        29.7 * PdfPageFormat.cm,
        21.0 * PdfPageFormat.cm,
        marginAll: 1.0 * PdfPageFormat.cm,
      ),
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      footer: (context) => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text(
          'Sayfa ${context.pageNumber} / ${context.pagesCount}',
          style: const pw.TextStyle(fontSize: 8),
        ),
      ),
      build: (_) => [
        pw.Text(
          '$year Yıllık Nöbet Özeti',
          style: pw.TextStyle(font: boldFont, fontSize: 16),
        ),
        pw.SizedBox(height: 4),
        pw.Text(YearlyExcel.monthsLine(summary), style: body),
        pw.SizedBox(height: 8),
        pw.TableHelper.fromTextArray(
          border: border,
          headerStyle: head,
          cellStyle: body,
          headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
          cellAlignment: pw.Alignment.centerRight,
          cellAlignments: {
            0: pw.Alignment.centerLeft,
            1: pw.Alignment.centerLeft,
          },
          headers: const [
            'Ad Soyad',
            'Görev',
            'Ay',
            'Toplam nöbet',
            'Hafta sonu nöbet',
            'Resmi tatil nöbeti',
            'Dini bayram nöbeti',
            'Gün aşırı çift',
            'Çalışılan saat',
            'Fazla mesai',
          ],
          data: [
            for (final r in summary.rows)
              [
                r.name,
                r.isChargeNurse ? 'Sorumlu hemşire' : r.role.label,
                n(r.totals.months),
                n(r.totals.shifts),
                n(r.totals.weekendShifts),
                n(r.totals.nationalHolidayShifts),
                n(r.totals.religiousHolidayShifts),
                n(r.totals.everyOtherDayPairs),
                n(r.totals.workedHours),
                n(r.totals.overtimeHours),
              ],
          ],
        ),
        pw.SizedBox(height: 14),
        pw.Text(
          'Aylara göre karşılaştırma',
          style: pw.TextStyle(font: boldFont, fontSize: 12),
        ),
        pw.Text(
          'Renk, kişinin o ay aynı görevdeki ortalamadan farkı: kırmızı = '
          'ortalamanın üstü, mavi = altı.',
          style: body,
        ),
        for (final metric in YearlyReport.metrics) comparison(metric),
      ],
    ),
  );
  return doc.save();
}
