import 'dart:typed_data';

import 'attendance_sheet.dart';
import 'turkish_dates.dart';
import 'xlsx_writer.dart';

/// Puantaj cetvelini Excel'e döker (saf Dart): kişi × gün kodları, toplamlar,
/// açıklama ve imza alanları.
class AttendanceExcel {
  const AttendanceExcel._();

  static const _closed = 0xCAE2DC;
  static const _header = 0xEEEEEE;
  static const _off = 0xF2F2F2;
  static const _weekdays = ['Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz'];

  static String title(int year, int month) =>
      '${turkishMonthNames[month - 1]} $year Puantaj Cetveli';

  static Uint8List build({
    required int year,
    required int month,
    required List<AttendanceRow> rows,
    required Set<int> closedDays,
    Map<String, double> workedHours = const {},
    String institution = '',
    String unit = '',
    String preparedBy = '',
    String approvedBy = '',
    Iterable<String> customCodes = const [],
  }) {
    final days = DateTime(year, month + 1, 0).day;
    const center = XlsxStyle(align: XlsxAlign.center);
    const head = XlsxStyle(
      bold: true,
      fill: _header,
      align: XlsxAlign.center,
      wrap: true,
    );
    final header = [
      const XlsxCell('Sıra', style: head),
      const XlsxCell('Ad Soyad', style: head),
      const XlsxCell('Unvan', style: head),
      for (var d = 1; d <= days; d++)
        XlsxCell(
          '$d\n${_weekdays[DateTime(year, month, d).weekday - 1]}',
          style: head.copyWith(
            fill: closedDays.contains(d) ? _closed : _header,
          ),
        ),
      const XlsxCell('Nöbet', style: head),
      const XlsxCell('7A', style: head),
      const XlsxCell(AttendanceSheet.offCode, style: head),
      const XlsxCell('İzin / rapor', style: head),
      if (workedHours.isNotEmpty) const XlsxCell('Çalışılan saat', style: head),
    ];
    final out = <List<XlsxCell>>[
      if (institution.isNotEmpty)
        [
          XlsxCell(
            institution,
            style: const XlsxStyle(bold: true, border: false),
          ),
        ],
      if (unit.isNotEmpty)
        [XlsxCell(unit, style: const XlsxStyle(border: false))],
      [
        XlsxCell(
          title(year, month),
          style: const XlsxStyle(bold: true, border: false),
        ),
      ],
      header,
      for (final (i, r) in rows.indexed)
        [
          XlsxCell(i + 1, style: center),
          XlsxCell(r.name),
          XlsxCell(r.title),
          for (var d = 1; d <= days; d++)
            XlsxCell(
              r.codes[d - 1].isEmpty ? null : r.codes[d - 1],
              style: center.copyWith(
                fill: closedDays.contains(d)
                    ? _closed
                    : r.codes[d - 1] == AttendanceSheet.offCode
                    ? _off
                    : null,
                bold:
                    r.codes[d - 1].isNotEmpty &&
                    r.codes[d - 1] != AttendanceSheet.offCode &&
                    !r.codes[d - 1].endsWith('.'),
              ),
            ),
          XlsxCell(r.shifts, style: center),
          XlsxCell(r.dayShifts, style: center),
          XlsxCell(r.offDays, style: center),
          XlsxCell(r.leaveDays, style: center),
          if (workedHours.isNotEmpty)
            XlsxCell(workedHours[r.personId] ?? 0, style: center),
        ],
      const [],
      for (final l in AttendanceSheet.legend(customCodes: customCodes))
        [XlsxCell(l, style: const XlsxStyle(border: false))],
      const [],
      [
        XlsxCell(
          'Hazırlayan: ${preparedBy.isEmpty ? '' : preparedBy}',
          style: const XlsxStyle(bold: true, border: false),
        ),
        const XlsxCell(null, style: XlsxStyle(border: false)),
        XlsxCell(
          'Onaylayan: ${approvedBy.isEmpty ? '' : approvedBy}',
          style: const XlsxStyle(bold: true, border: false),
        ),
      ],
    ];
    final headerRow = out.indexOf(header);
    return XlsxWriter.build([
      XlsxSheet(
        'Puantaj',
        rows: out,
        columnWidths: {
          0: 5,
          1: 22,
          2: 18,
          for (var c = 3; c < 3 + days; c++) c: 5.2,
          for (var c = 3 + days; c < 8 + days; c++) c: 8,
        },
        rowHeights: {headerRow: 30},
        freezeRows: headerRow + 1,
        freezeColumns: 2,
        printLandscape: true,
      ),
    ]);
  }
}
