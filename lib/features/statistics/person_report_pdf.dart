import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../logic/person_totals.dart';
import '../../logic/totals_columns.dart';
import '../../logic/turkish_dates.dart';
import '../../logic/yearly_summary.dart';
import '../../models/models.dart';

const _primary = PdfColor.fromInt(0xFF0F7A61);
const _primaryDark = PdfColor.fromInt(0xFF0A5847);
const _tint = PdfColor.fromInt(0xFFE6F2EE);
const _line = PdfColor.fromInt(0xFFB0BEC5);
const _muted = PdfColor.fromInt(0xFF607D8B);

/// Bir kişinin yıllık nöbet karnesi (A4 dikey): özet kutuları (rol
/// ortalamasıyla), aylara göre tablo (nöbet, hafta sonu, resmi tatil, dini
/// bayram, gün aşırı çift, 4–5 gün ara, çalışılan / gereken / fazla saat),
/// yıl toplamı ve rol ortalaması satırları.
Future<Uint8List> buildPersonReportPdf({
  required int year,
  required YearlyRow row,
  required YearlySummary summary,
  required pw.Font font,
  required pw.Font boldFont,
  DateTime? createdAt,
  Set<TotalsColumn> columns = const {...TotalsColumn.values},
}) async {
  final doc = pw.Document(
    title: '${row.name} · $year Nöbet Karnesi',
    theme: pw.ThemeData.withFont(base: font, bold: boldFont),
  );
  String n(num v) => NumberFormat('#,##0.#', 'tr_TR').format(v);
  final created = DateFormat(
    'd MMMM y',
    'tr_TR',
  ).format(createdAt ?? DateTime.now());
  double mean(num Function(PersonTotals) pick) =>
      summary.roleMean(row.role, pick);
  final role = row.isChargeNurse
      ? 'Sorumlu hemşire'
      : row.role == Role.nurse
      ? 'Hemşire'
      : 'Radyoloji teknikeri';

  final shown = [
    for (final c in TotalsColumn.ordered(columns)) (c.label, c.valueOf),
  ];
  bool has(TotalsColumn c) => columns.contains(c);

  pw.Widget cell(String text, {bool bold = false, PdfColor? color}) =>
      pw.Container(
        alignment: pw.Alignment.center,
        padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 5),
        child: pw.Text(
          text,
          style: pw.TextStyle(
            fontSize: 9,
            fontWeight: bold ? pw.FontWeight.bold : null,
            color: color,
          ),
        ),
      );

  pw.Widget box(String label, num value, num average, {String unit = ''}) =>
      pw.Expanded(
        child: pw.Container(
          margin: const pw.EdgeInsets.symmetric(horizontal: 4),
          padding: const pw.EdgeInsets.all(10),
          decoration: pw.BoxDecoration(
            color: _tint,
            borderRadius: pw.BorderRadius.circular(8),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                label,
                style: const pw.TextStyle(fontSize: 8.5, color: _muted),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                '${n(value)}$unit',
                style: pw.TextStyle(
                  fontSize: 18,
                  fontWeight: pw.FontWeight.bold,
                  color: _primaryDark,
                ),
              ),
              pw.Text(
                row.isChargeNurse ? ' ' : 'Rol ortalaması ${n(average)}$unit',
                style: const pw.TextStyle(fontSize: 8, color: _muted),
              ),
            ],
          ),
        ),
      );

  final t = row.totals;
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4.copyWith(
        marginLeft: 1.4 * PdfPageFormat.cm,
        marginRight: 1.4 * PdfPageFormat.cm,
        marginTop: 1.2 * PdfPageFormat.cm,
        marginBottom: 1.2 * PdfPageFormat.cm,
      ),
      footer: (context) => pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'Nöbetçi · $created',
            style: const pw.TextStyle(fontSize: 8, color: _muted),
          ),
          pw.Text(
            'Sayfa ${context.pageNumber} / ${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 8, color: _muted),
          ),
        ],
      ),
      build: (_) => [
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.all(16),
          decoration: pw.BoxDecoration(
            color: _primary,
            borderRadius: pw.BorderRadius.circular(10),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                row.name,
                style: pw.TextStyle(
                  fontSize: 20,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.white,
                ),
              ),
              pw.SizedBox(height: 2),
              pw.Text(
                '$role · $year nöbet karnesi',
                style: const pw.TextStyle(fontSize: 11, color: PdfColors.white),
              ),
              pw.SizedBox(height: 2),
              pw.Text(
                'Dahil aylar: '
                '${[for (final m in summary.months) turkishMonthNames[m - 1]].join(', ')}',
                style: const pw.TextStyle(fontSize: 9, color: PdfColors.white),
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 12),
        pw.Row(
          children: [
            if (has(TotalsColumn.shifts))
              box('Toplam nöbet', t.shifts, mean((t) => t.shifts)),
            if (has(TotalsColumn.weekend))
              box('Hafta sonu', t.weekendShifts, mean((t) => t.weekendShifts)),
            if (has(TotalsColumn.nationalHoliday) ||
                has(TotalsColumn.religiousHoliday))
              box(
                'Tatil + bayram',
                t.nationalHolidayShifts + t.religiousHolidayShifts,
                mean((t) => t.nationalHolidayShifts + t.religiousHolidayShifts),
              ),
            if (has(TotalsColumn.overtime))
              box(
                'Fazla mesai',
                t.overtimeHours,
                mean((t) => t.overtimeHours),
                unit: ' sa',
              ),
          ],
        ),
        pw.SizedBox(height: 16),
        pw.Text(
          'Aylara göre',
          style: pw.TextStyle(
            fontSize: 12,
            fontWeight: pw.FontWeight.bold,
            color: _primary,
          ),
        ),
        pw.SizedBox(height: 6),
        pw.Table(
          border: pw.TableBorder.all(color: _line, width: 0.5),
          columnWidths: const {0: pw.FlexColumnWidth(1.6)},
          children: [
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: _primary),
              children: [
                cell('Ay', bold: true, color: PdfColors.white),
                for (final (label, _) in shown)
                  cell(label, bold: true, color: PdfColors.white),
              ],
            ),
            for (final m in summary.months)
              pw.TableRow(
                children: [
                  cell(turkishMonthNames[m - 1]),
                  for (final (_, pick) in shown)
                    row.byMonth[m] == null
                        ? cell('–', color: _muted)
                        : cell(n(pick(row.byMonth[m]!))),
                ],
              ),
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: _tint),
              children: [
                cell('Toplam', bold: true),
                for (final (_, pick) in shown) cell(n(pick(t)), bold: true),
              ],
            ),
            if (!row.isChargeNurse)
              pw.TableRow(
                children: [
                  cell('Rol ortalaması', color: _muted),
                  for (final (_, pick) in shown)
                    cell(n(mean(pick)), color: _muted),
                ],
              ),
          ],
        ),
        pw.SizedBox(height: 10),
        pw.Text(
          'Rol ortalaması aynı görevdeki kişilerin (sorumlu hemşire hariç) '
          'yıllık toplamlarının ortalamasıdır. "–": o ay listede yok '
          '(izin, pasif ya da işe başlamadan önce).',
          style: const pw.TextStyle(fontSize: 8, color: _muted),
        ),
      ],
    ),
  );
  return doc.save();
}
