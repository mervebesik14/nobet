import 'dart:typed_data';

import 'turkish_dates.dart';
import 'xlsx_writer.dart';
import 'yearly_report.dart';
import 'yearly_summary.dart';

/// Yıllık özeti Excel'e döker (saf Dart): "Yıllık Özet" sayfası kişi başı
/// toplamlar, "Aylara Göre" sayfası her ölçü için kişi × ay tablosu
/// (ortalamanın üstü kırmızı, altı mavi).
class YearlyExcel {
  const YearlyExcel._();

  static const _header = 0xEEEEEE;
  static const _head = XlsxStyle(bold: true, fill: _header, wrap: true);
  static const _number = XlsxStyle(align: XlsxAlign.right);
  static const _title = XlsxStyle(bold: true, border: false);

  static num _round(num v) => v is double ? (v * 10).roundToDouble() / 10 : v;

  static Uint8List build({required int year, required YearlySummary summary}) =>
      XlsxWriter.build([_totals(year, summary), _byMonth(year, summary)]);

  static String monthsLine(YearlySummary summary) =>
      'Dahil aylar: '
      '${summary.months.map((m) => turkishMonthNames[m - 1]).join(', ')}';

  static XlsxSheet _totals(int year, YearlySummary summary) {
    XlsxCell n(num v) => XlsxCell(_round(v), style: _number);
    const headers = [
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
    ];
    return XlsxSheet(
      'Yıllık Özet',
      rows: [
        [XlsxCell('$year Yıllık Nöbet Özeti', style: _title)],
        [XlsxCell(monthsLine(summary), style: const XlsxStyle(border: false))],
        [for (final h in headers) XlsxCell(h, style: _head)],
        for (final r in summary.rows)
          [
            XlsxCell(r.name),
            XlsxCell(r.isChargeNurse ? 'Sorumlu hemşire' : r.role.label),
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
      columnWidths: {
        0: 24,
        1: 22,
        for (var i = 2; i < headers.length; i++) i: 11,
      },
      rowHeights: const {2: 30},
      freezeRows: 3,
      freezeColumns: 1,
      printLandscape: true,
    );
  }

  static XlsxSheet _byMonth(int year, YearlySummary summary) {
    final months = summary.months;
    final rows = <List<XlsxCell>>[
      [XlsxCell('$year Aylara Göre Karşılaştırma', style: _title)],
      [
        const XlsxCell(
          'Renk, kişinin o ay aynı görevdeki ortalamadan farkı: kırmızı = '
          'ortalamanın üstü, mavi = altı.',
          style: XlsxStyle(border: false),
        ),
      ],
    ];
    for (final metric in YearlyReport.metrics) {
      rows
        ..add(const [])
        ..add([
          XlsxCell(metric.label, style: _head),
          for (final m in months)
            XlsxCell(
              turkishMonthNames[m - 1],
              style: _head.copyWith(align: XlsxAlign.center),
            ),
          const XlsxCell('Toplam', style: _head),
        ]);
      for (final r in summary.rows) {
        rows.add([
          XlsxCell(r.name),
          for (final m in months)
            if (r.byMonth[m] case final t?)
              XlsxCell(
                _round(metric.pick(t)),
                style: XlsxStyle(
                  align: XlsxAlign.center,
                  fill: YearlyReport.tint(summary.deviation(r, m, metric.pick)),
                ),
              )
            else
              const XlsxCell.empty(),
          XlsxCell(
            _round(metric.pick(r.totals)),
            style: const XlsxStyle(bold: true, align: XlsxAlign.right),
          ),
        ]);
      }
    }
    return XlsxSheet(
      'Aylara Göre',
      rows: rows,
      columnWidths: {
        0: 24,
        for (var i = 1; i <= months.length; i++) i: 9,
        months.length + 1: 9,
      },
      freezeColumns: 1,
      printLandscape: true,
    );
  }
}
