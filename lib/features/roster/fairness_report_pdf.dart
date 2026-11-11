import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../logic/fairness_report.dart';
import '../../logic/turkish_collation.dart';
import '../../logic/turkish_dates.dart';
import '../../models/models.dart';
import '../settings/report_info.dart';

const _primary = PdfColor.fromInt(0xFF0F7A61);
const _tint = PdfColor.fromInt(0xFFE6F2EE);
const _line = PdfColor.fromInt(0xFFB0BEC5);
const _muted = PdfColor.fromInt(0xFF607D8B);
const _warn = PdfColor.fromInt(0xFFB3261E);
const _okBg = PdfColor.fromInt(0xFFE6F2EE);
const _warnBg = PdfColor.fromInt(0xFFFBE9E7);

/// Adalet belgesi (A4 dikey): listenin nasıl dağıtıldığı. Uygulanan
/// kurallar, rol başına denge özeti (farklar), kişi başı bu ay ve yıl içi
/// sayılar, istek karşılanma.
Future<Uint8List> buildFairnessReportPdf({
  required int year,
  required int month,
  required FairnessReport report,
  required ReportInfo info,
  required pw.Font font,
  required pw.Font boldFont,
  DateTime? createdAt,
}) async {
  final monthLabel = '${turkishMonthNames[month - 1]} $year';
  final doc = pw.Document(
    title: '$monthLabel nöbet dağılımı',
    theme: pw.ThemeData.withFont(base: font, bold: boldFont),
  );
  final date = DateFormat(
    'd MMMM y',
    'tr_TR',
  ).format(createdAt ?? DateTime.now());

  const headStyle = pw.TextStyle(fontSize: 8, color: PdfColors.white);
  pw.Widget cell(
    String text, {
    bool bold = false,
    pw.Alignment align = pw.Alignment.center,
  }) => pw.Container(
    alignment: align,
    padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 4),
    child: pw.Text(
      text,
      style: pw.TextStyle(
        fontSize: 8.5,
        fontWeight: bold ? pw.FontWeight.bold : null,
      ),
    ),
  );
  pw.Widget head(String text) => pw.Container(
    alignment: pw.Alignment.center,
    padding: const pw.EdgeInsets.symmetric(horizontal: 2, vertical: 4),
    child: pw.Text(text, style: headStyle, textAlign: pw.TextAlign.center),
  );
  pw.Widget section(String text) => pw.Padding(
    padding: const pw.EdgeInsets.only(top: 12, bottom: 5),
    child: pw.Text(
      text,
      style: pw.TextStyle(
        fontSize: 11,
        fontWeight: pw.FontWeight.bold,
        color: _primary,
      ),
    ),
  );

  pw.Widget balanceBox(Role role, List<FairnessCheck> checks) {
    final ok = report.balancedFor(role);
    return pw.Container(
      width: double.infinity,
      margin: const pw.EdgeInsets.only(bottom: 6),
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        color: ok ? _okBg : _warnBg,
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            '${role.pluralLabel}: '
            '${ok ? 'dengeli (her ölçüde fark en fazla ${FairnessReport.balanced})' : 'farkı 1\'i aşan ölçü var'}',
            style: pw.TextStyle(
              fontSize: 9.5,
              fontWeight: pw.FontWeight.bold,
              color: ok ? _primary : _warn,
            ),
          ),
          pw.SizedBox(height: 3),
          pw.Wrap(
            spacing: 12,
            runSpacing: 2,
            children: [
              for (final c in checks)
                pw.Text(
                  '${c.label}: ${c.spread}',
                  style: pw.TextStyle(
                    fontSize: 9,
                    color: c.spread > FairnessReport.balanced ? _warn : null,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  pw.Widget table(Role role) {
    final rows = [
      for (final r in report.rows)
        if (r.role == role) r,
    ];
    final group = rows.where((r) => !r.isChargeNurse).toList();
    String mean(int Function(FairnessRow) pick) => group.isEmpty
        ? ''
        : NumberFormat(
            '#,##0.#',
            'tr_TR',
          ).format(group.fold(0, (s, r) => s + pick(r)) / group.length);
    return pw.Table(
      border: pw.TableBorder.all(color: _line, width: 0.5),
      columnWidths: const {0: pw.FlexColumnWidth(3)},
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: _primary),
          children: [
            head('Ad Soyad'),
            head('Nöbet'),
            head('Hafta sonu'),
            head('Cuma'),
            head('Tatil / bayram'),
            head('Gün aşırı çift'),
            head('Yıl içi nöbet'),
            head('Yıl içi hafta sonu'),
            head('Yıl içi tatil'),
            head('İstek'),
          ],
        ),
        for (final (i, r) in rows.indexed)
          pw.TableRow(
            decoration: i.isOdd ? const pw.BoxDecoration(color: _tint) : null,
            children: [
              cell(
                r.isChargeNurse ? '${r.name} (sorumlu)' : r.name,
                align: pw.Alignment.centerLeft,
              ),
              cell('${r.shifts}', bold: true),
              cell('${r.weekend}'),
              cell('${r.preWeekend}'),
              cell('${r.holiday}'),
              cell('${r.pairs}'),
              cell('${r.ytdShifts}'),
              cell('${r.ytdWeekend}'),
              cell('${r.ytdHoliday}'),
              cell(
                r.requestsTotal == 0
                    ? '–'
                    : '${r.requestsMet}/${r.requestsTotal}',
              ),
            ],
          ),
        if (group.length > 1)
          pw.TableRow(
            decoration: const pw.BoxDecoration(color: _tint),
            children: [
              cell('Ortalama', bold: true, align: pw.Alignment.centerLeft),
              cell(mean((r) => r.shifts), bold: true),
              cell(mean((r) => r.weekend)),
              cell(mean((r) => r.preWeekend)),
              cell(mean((r) => r.holiday)),
              cell(mean((r) => r.pairs)),
              cell(mean((r) => r.ytdShifts)),
              cell(mean((r) => r.ytdWeekend)),
              cell(mean((r) => r.ytdHoliday)),
              cell(''),
            ],
          ),
      ],
    );
  }

  final roles = [
    for (final role in Role.values)
      if (report.rows.any((r) => r.role == role)) role,
  ];

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4.copyWith(
        marginLeft: 1.4 * PdfPageFormat.cm,
        marginRight: 1.4 * PdfPageFormat.cm,
        marginTop: 1.3 * PdfPageFormat.cm,
        marginBottom: 1.3 * PdfPageFormat.cm,
      ),
      footer: (context) => pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'Nöbetçi ile hazırlandı · $date',
            style: const pw.TextStyle(fontSize: 8, color: _muted),
          ),
          pw.Text(
            'Sayfa ${context.pageNumber} / ${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 8, color: _muted),
          ),
        ],
      ),
      build: (_) => [
        if (info.institution.isNotEmpty)
          pw.Text(
            turkishUpperCase(info.institution),
            style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
          ),
        if (info.unit.isNotEmpty)
          pw.Text(info.unit, style: const pw.TextStyle(fontSize: 10)),
        pw.SizedBox(height: 4),
        pw.Text(
          '$monthLabel · Nöbetler nasıl dağıtıldı?',
          style: pw.TextStyle(
            fontSize: 16,
            fontWeight: pw.FontWeight.bold,
            color: _primary,
          ),
        ),
        pw.SizedBox(height: 3),
        pw.Text(
          'Bu belge listenin hangi kurallarla ve ne kadar eşit dağıtıldığını '
          'gösterir. "Fark": rolde en çok ve en az tutan arasındaki fark.',
          style: const pw.TextStyle(fontSize: 9, color: _muted),
        ),
        section('Denge özeti'),
        for (final role in roles)
          if (report.checks[role] case final checks?) balanceBox(role, checks),
        if (report.requestsTotal > 0)
          pw.Text(
            'İstekler: ${report.requestsTotal} isteğin '
            '${report.requestsMet} tanesi karşılandı '
            '(%${report.requestPercent}).',
            style: const pw.TextStyle(fontSize: 9.5),
          ),
        section('Uygulanan kurallar'),
        for (final r in report.rules)
          pw.Bullet(
            text: r,
            style: const pw.TextStyle(fontSize: 9),
            bulletSize: 3,
            bulletColor: _primary,
            margin: const pw.EdgeInsets.only(bottom: 2),
          ),
        for (final role in roles) ...[section(role.pluralLabel), table(role)],
        pw.SizedBox(height: 6),
        pw.Text(
          'Cuma: ertesi günü hafta sonu ya da tatil olan nöbet (hafta sonunun '
          'yarısı uykuyla geçer). Yıl içi: yılbaşından bu ay dahil. İstek: '
          'istemediği gün, izin, tercih ve fazla mesai isteklerinden '
          'karşılananlar.',
          style: const pw.TextStyle(fontSize: 8, color: _muted),
        ),
      ],
    ),
  );
  return doc.save();
}
