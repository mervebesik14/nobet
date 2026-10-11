import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../logic/roster_summary.dart';
import '../../models/models.dart';
import 'roster_table.dart';

/// Nöbet listesini PDF'e çevirir: başlıkta ay/yıl, nöbet tablosu (satırlarda
/// kişiler, nöbet günlerinde nöbet süresi) ve özet tablo. Türkçe karakterler
/// için [font] / [boldFont] gömülür.
///
/// [singlePage] true ise içerik tek, içeriğe göre uzayan bir sayfaya dizilir
/// (PNG görsel üretmek için); değilse A4 yatay, gerekirse çok sayfa.
Future<Uint8List> buildRosterPdf({
  required MonthPlan plan,
  required List<RosterRow> rows,
  required RosterSummary summary,
  required Set<int> weekendDays,
  required Set<int> holidayDays,
  required int shiftHours,
  required pw.Font font,
  required pw.Font boldFont,
  Map<int, int> missingByDay = const {},
  bool singlePage = false,
}) async {
  final title =
      '${DateFormat.yMMMM('tr_TR').format(DateTime(plan.year, plan.month))} '
      'Nöbet Listesi';
  final theme = pw.ThemeData.withFont(base: font, bold: boldFont);
  final content = <pw.Widget>[
    pw.Text(title, style: pw.TextStyle(font: boldFont, fontSize: 16)),
    pw.SizedBox(height: 8),
    _rosterTable(
      plan: plan,
      rows: rows,
      weekendDays: weekendDays,
      holidayDays: holidayDays,
      shiftHours: shiftHours,
      missingByDay: missingByDay,
      boldFont: boldFont,
    ),
    pw.SizedBox(height: 4),
    pw.Row(
      children: [
        _legend(_weekendColor, 'Hafta sonu'),
        pw.SizedBox(width: 12),
        _legend(_holidayColor, 'Resmi tatil'),
      ],
    ),
    pw.SizedBox(height: 14),
    pw.Text('Özet', style: pw.TextStyle(font: boldFont, fontSize: 12)),
    pw.SizedBox(height: 4),
    _summaryTable(summary, boldFont),
  ];

  final doc = pw.Document(title: title, theme: theme);
  const landscape = PdfPageFormat(
    29.7 * PdfPageFormat.cm,
    21.0 * PdfPageFormat.cm,
    marginAll: 1.0 * PdfPageFormat.cm,
  );
  if (singlePage) {
    doc.addPage(
      pw.Page(
        pageFormat: landscape.copyWith(height: double.infinity),
        build: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: content,
        ),
      ),
    );
  } else {
    doc.addPage(
      pw.MultiPage(
        pageFormat: landscape,
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        footer: (context) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'Sayfa ${context.pageNumber} / ${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 8),
          ),
        ),
        build: (_) => content,
      ),
    );
  }
  return doc.save();
}

const _weekendColor = PdfColor.fromInt(0xFFE3ECEB);
const _holidayColor = PdfColor.fromInt(0xFFF6E1C4);
const _groupColor = PdfColor.fromInt(0xFFB9E9E1);
const _missingColor = PdfColor.fromInt(0xFFF9D6D2);

pw.Widget _legend(PdfColor color, String label) => pw.Row(
  children: [
    pw.Container(width: 8, height: 8, color: color),
    pw.SizedBox(width: 4),
    pw.Text(label, style: const pw.TextStyle(fontSize: 7)),
  ],
);

pw.Widget _rosterTable({
  required MonthPlan plan,
  required List<RosterRow> rows,
  required Set<int> weekendDays,
  required Set<int> holidayDays,
  required int shiftHours,
  required Map<int, int> missingByDay,
  required pw.Font boldFont,
}) {
  final days = [for (var d = 1; d <= plan.daysInMonth; d++) d];
  final weekday = DateFormat.E('tr_TR');
  final worked = <String, Set<int>>{};
  for (final a in plan.assignments.values) {
    for (final id in a.personIds) {
      (worked[id] ??= {}).add(a.day);
    }
  }

  PdfColor? columnColor(int d) => holidayDays.contains(d)
      ? _holidayColor
      : weekendDays.contains(d)
      ? _weekendColor
      : null;

  pw.Widget cell(String text, {PdfColor? color, bool bold = false}) =>
      pw.Container(
        color: color,
        alignment: pw.Alignment.center,
        padding: const pw.EdgeInsets.symmetric(vertical: 2),
        child: pw.Text(
          text,
          style: pw.TextStyle(fontSize: 7, font: bold ? boldFont : null),
          textAlign: pw.TextAlign.center,
        ),
      );

  pw.Widget nameCell(String text, {PdfColor? color, bool bold = false}) =>
      pw.Container(
        color: color,
        padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 2),
        child: pw.Text(
          text,
          maxLines: 1,
          style: pw.TextStyle(fontSize: 7, font: bold ? boldFont : null),
        ),
      );

  final tableRows = <pw.TableRow>[
    pw.TableRow(
      repeat: true,
      children: [
        nameCell('Ad Soyad', bold: true),
        for (final d in days)
          cell(
            '$d\n${weekday.format(DateTime(plan.year, plan.month, d))}',
            color: columnColor(d),
            bold: true,
          ),
      ],
    ),
  ];
  Role? currentRole;
  for (final row in rows) {
    if (row.role != currentRole) {
      currentRole = row.role;
      tableRows.add(
        pw.TableRow(
          children: [
            nameCell(row.role.pluralLabel, color: _groupColor, bold: true),
            for (final _ in days) cell('', color: _groupColor),
          ],
        ),
      );
    }
    final personDays = worked[row.id] ?? const <int>{};
    tableRows.add(
      pw.TableRow(
        children: [
          nameCell(row.name),
          for (final d in days)
            cell(
              personDays.contains(d) ? '$shiftHours' : '',
              color: columnColor(d),
              bold: true,
            ),
        ],
      ),
    );
  }
  if (missingByDay.isNotEmpty) {
    tableRows.add(
      pw.TableRow(
        children: [
          nameCell('Eksik', color: _missingColor),
          for (final d in days)
            missingByDay.containsKey(d)
                ? cell('${missingByDay[d]}', color: _missingColor)
                : cell('', color: columnColor(d)),
        ],
      ),
    );
  }

  return pw.Table(
    border: pw.TableBorder.all(color: PdfColors.grey500, width: 0.4),
    // Renkli hücreler satırın tüm yüksekliğini doldursun.
    defaultVerticalAlignment: pw.TableCellVerticalAlignment.full,
    columnWidths: {
      0: const pw.FixedColumnWidth(95),
      for (var i = 1; i <= days.length; i++) i: const pw.FlexColumnWidth(),
    },
    children: tableRows,
  );
}

pw.Widget _summaryTable(RosterSummary summary, pw.Font boldFont) {
  final number = NumberFormat('#,##0.#', 'tr_TR');
  String n(num v) => number.format(v);
  return pw.TableHelper.fromTextArray(
    border: pw.TableBorder.all(color: PdfColors.grey500, width: 0.4),
    headerStyle: pw.TextStyle(font: boldFont, fontSize: 8),
    cellStyle: const pw.TextStyle(fontSize: 8),
    headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
    cellAlignment: pw.Alignment.centerRight,
    cellAlignments: {0: pw.Alignment.centerLeft, 1: pw.Alignment.centerLeft},
    headers: const [
      'Ad',
      'Görev',
      'Toplam nöbet',
      'Hafta sonu nöbet',
      'Gün aşırı çift',
      'Çalışılan saat',
      'Gereken saat',
      'Fazla mesai',
    ],
    data: [
      for (final r in summary.people)
        [
          r.name,
          r.role.label,
          n(r.shifts),
          n(r.weekendShifts),
          n(r.everyOtherDayPairs),
          n(r.workedHours),
          n(r.requiredHours),
          n(r.overtimeHours),
        ],
      for (final a in summary.averages.values)
        [
          'Ortalama',
          a.role.pluralLabel,
          n(a.shifts),
          n(a.weekendShifts),
          n(a.everyOtherDayPairs),
          n(a.workedHours),
          n(summary.requiredHours),
          n(a.overtimeHours),
        ],
    ],
  );
}
