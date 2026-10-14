import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../logic/personal_roster.dart';
import '../../logic/turkish_dates.dart';
import '../../models/models.dart';

/// Kişiye özel aylık nöbet programını A4 dikey PDF'e çevirir: renkli başlık,
/// özet kutuları, ay takvimi (nöbet / 7A / izin günleri işaretli) ve her
/// nöbet gününde birlikte nöbetçi olan hemşire ve radyoloji ekibi.
Future<Uint8List> buildPersonalRosterPdf({
  required PersonalRosterData data,
  required Set<int> weekendDays,
  required Set<int> holidayDays,
  required pw.Font font,
  required pw.Font boldFont,
  DateTime? createdAt,
}) async {
  final person = data.person;
  final title = '${person.name} · ${data.monthLabel} Nöbet Programı';
  final doc = pw.Document(
    title: title,
    theme: pw.ThemeData.withFont(base: font, bold: boldFont),
  );
  final created = DateFormat(
    'd MMMM y',
    'tr_TR',
  ).format(createdAt ?? DateTime.now());

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4.copyWith(
        marginLeft: 1.4 * PdfPageFormat.cm,
        marginRight: 1.4 * PdfPageFormat.cm,
        marginTop: 1.2 * PdfPageFormat.cm,
        marginBottom: 1.2 * PdfPageFormat.cm,
      ),
      footer: (context) => pw.Container(
        padding: const pw.EdgeInsets.only(top: 6),
        decoration: const pw.BoxDecoration(
          border: pw.Border(top: pw.BorderSide(color: _line, width: 0.5)),
        ),
        child: pw.Row(
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
      ),
      build: (_) => [
        _header(data),
        pw.SizedBox(height: 14),
        _stats(data),
        pw.SizedBox(height: 18),
        _sectionTitle('Takvim'),
        pw.SizedBox(height: 6),
        _calendar(data, weekendDays, holidayDays),
        pw.SizedBox(height: 6),
        _legend(data),
        pw.SizedBox(height: 18),
        _sectionTitle('Nöbet günleri ve ekip'),
        pw.SizedBox(height: 6),
        if (data.shifts.isEmpty)
          pw.Text(
            'Bu ay nöbet yok.',
            style: const pw.TextStyle(fontSize: 10, color: _muted),
          )
        else
          _shiftTable(data),
        if (data.leaves.isNotEmpty || data.dayShiftDays.isNotEmpty) ...[
          pw.SizedBox(height: 14),
          _notes(data),
        ],
      ],
    ),
  );
  return doc.save();
}

const _primary = PdfColor.fromInt(0xFF00695C);
const _primaryDark = PdfColor.fromInt(0xFF004D40);
const _primaryTint = PdfColor.fromInt(0xFFE0F2F1);
const _secondaryTint = PdfColor.fromInt(0xFFB2DFDB);
const _weekendTint = PdfColor.fromInt(0xFFF1F5F4);
const _holidayTint = PdfColor.fromInt(0xFFFFF6BF);
const _dayShift = PdfColor.fromInt(0xFFB26A00);
const _dayShiftTint = PdfColor.fromInt(0xFFF8E6CC);
const _line = PdfColor.fromInt(0xFFCFD8DC);
const _muted = PdfColor.fromInt(0xFF607D8B);
const _ink = PdfColor.fromInt(0xFF263238);

const _leaveInk = {
  LeaveType.annual: PdfColor.fromInt(0xFF2E7D8A),
  LeaveType.radiation: PdfColor.fromInt(0xFF7E57C2),
  LeaveType.sick: PdfColor.fromInt(0xFFC2185B),
};
const _leaveTint = {
  LeaveType.annual: PdfColor.fromInt(0xFFD5E9EC),
  LeaveType.radiation: PdfColor.fromInt(0xFFE8E0F4),
  LeaveType.sick: PdfColor.fromInt(0xFFF6D5E1),
};

pw.Widget _header(PersonalRosterData data) {
  final person = data.person;
  final role = person.isChargeNurse ? 'Sorumlu hemşire' : person.role.label;
  return pw.Container(
    padding: const pw.EdgeInsets.fromLTRB(18, 16, 18, 16),
    decoration: const pw.BoxDecoration(
      gradient: pw.LinearGradient(colors: [_primaryDark, _primary]),
      borderRadius: pw.BorderRadius.all(pw.Radius.circular(10)),
    ),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                person.name,
                style: pw.TextStyle(
                  fontSize: 22,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.white,
                ),
              ),
              pw.SizedBox(height: 3),
              pw.Text(
                role,
                style: const pw.TextStyle(fontSize: 11, color: _secondaryTint),
              ),
            ],
          ),
        ),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text(
              data.monthLabel,
              style: pw.TextStyle(
                fontSize: 16,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.white,
              ),
            ),
            pw.SizedBox(height: 3),
            pw.Text(
              'Nöbet Programı',
              style: const pw.TextStyle(fontSize: 11, color: _secondaryTint),
            ),
          ],
        ),
      ],
    ),
  );
}

pw.Widget _stats(PersonalRosterData data) {
  final items = <(String, String)>[
    ('${data.shifts.length}', 'Nöbet'),
    ('${data.weekendShifts}', 'Hafta sonu / tatil'),
    if (data.dayShiftDays.isNotEmpty) ('${data.dayShiftDays.length}', '7A gün'),
    if (data.leaveDayCount > 0) ('${data.leaveDayCount}', 'İzin / rapor gün'),
  ];
  return pw.Row(
    children: [
      for (var i = 0; i < items.length; i++) ...[
        if (i > 0) pw.SizedBox(width: 8),
        pw.Expanded(
          child: pw.Container(
            padding: const pw.EdgeInsets.symmetric(vertical: 10),
            decoration: const pw.BoxDecoration(
              color: _primaryTint,
              borderRadius: pw.BorderRadius.all(pw.Radius.circular(8)),
            ),
            child: pw.Column(
              children: [
                pw.Text(
                  items[i].$1,
                  style: pw.TextStyle(
                    fontSize: 20,
                    fontWeight: pw.FontWeight.bold,
                    color: _primaryDark,
                  ),
                ),
                pw.SizedBox(height: 2),
                pw.Text(
                  items[i].$2,
                  textAlign: pw.TextAlign.center,
                  style: const pw.TextStyle(fontSize: 8, color: _muted),
                ),
              ],
            ),
          ),
        ),
      ],
    ],
  );
}

pw.Widget _sectionTitle(String text) => pw.Row(
  children: [
    pw.Container(width: 4, height: 14, color: _primary),
    pw.SizedBox(width: 6),
    pw.Text(
      text,
      style: pw.TextStyle(
        fontSize: 13,
        fontWeight: pw.FontWeight.bold,
        color: _ink,
      ),
    ),
  ],
);

pw.Widget _calendar(
  PersonalRosterData data,
  Set<int> weekendDays,
  Set<int> holidayDays,
) {
  final shiftByDay = {for (final s in data.shifts) s.day: s.shift};
  final dayShift = data.dayShiftDays.toSet();
  final leaveByDay = data.leaveByDay;
  final daysInMonth = DateTime(data.year, data.month + 1, 0).day;
  final offset = DateTime(data.year, data.month).weekday - 1;
  const weekdays = ['Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz'];

  pw.Widget cell(int? day) {
    if (day == null) return pw.Container(height: 44);
    final shift = shiftByDay[day];
    final leave = leaveByDay[day];
    final isDayShift = shift == null && dayShift.contains(day);
    final PdfColor background;
    PdfColor? badgeColor;
    String? badge;
    if (shift != null) {
      background = _primary;
      badge = shift;
    } else if (isDayShift) {
      background = _dayShiftTint;
      badge = '7A';
      badgeColor = _dayShift;
    } else if (leave != null) {
      background = _leaveTint[leave]!;
      badge = leave.shortLabel;
      badgeColor = _leaveInk[leave];
    } else if (holidayDays.contains(day)) {
      background = _holidayTint;
    } else if (weekendDays.contains(day)) {
      background = _weekendTint;
    } else {
      background = PdfColors.white;
    }
    final onShift = shift != null;
    return pw.Container(
      height: 44,
      padding: const pw.EdgeInsets.all(4),
      decoration: pw.BoxDecoration(
        color: background,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5)),
        border: onShift ? null : pw.Border.all(color: _line, width: 0.5),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            '$day',
            style: pw.TextStyle(
              fontSize: 9,
              fontWeight: pw.FontWeight.bold,
              color: onShift ? PdfColors.white : _ink,
            ),
          ),
          pw.Spacer(),
          if (badge != null)
            pw.Align(
              alignment: pw.Alignment.bottomRight,
              child: pw.Text(
                badge,
                style: pw.TextStyle(
                  fontSize: onShift ? 13 : 10,
                  fontWeight: pw.FontWeight.bold,
                  color: onShift ? PdfColors.white : badgeColor,
                ),
              ),
            ),
        ],
      ),
    );
  }

  final cells = <int?>[
    for (var i = 0; i < offset; i++) null,
    for (var d = 1; d <= daysInMonth; d++) d,
  ];
  while (cells.length % 7 != 0) {
    cells.add(null);
  }
  pw.Widget row(List<pw.Widget> children) => pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 4),
    child: pw.Row(
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) pw.SizedBox(width: 4),
          pw.Expanded(child: children[i]),
        ],
      ],
    ),
  );

  return pw.Column(
    children: [
      row([
        for (final (i, w) in weekdays.indexed)
          pw.Center(
            child: pw.Text(
              w,
              style: pw.TextStyle(
                fontSize: 8,
                fontWeight: pw.FontWeight.bold,
                color: i >= 5 ? _primary : _muted,
              ),
            ),
          ),
      ]),
      for (var i = 0; i < cells.length; i += 7)
        row([for (final d in cells.sublist(i, i + 7)) cell(d)]),
    ],
  );
}

pw.Widget _legend(PersonalRosterData data) {
  pw.Widget item(PdfColor color, String label, {PdfColor? border}) => pw.Row(
    mainAxisSize: pw.MainAxisSize.min,
    children: [
      pw.Container(
        width: 9,
        height: 9,
        decoration: pw.BoxDecoration(
          color: color,
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(2)),
          border: border == null
              ? null
              : pw.Border.all(color: border, width: 0.5),
        ),
      ),
      pw.SizedBox(width: 4),
      pw.Text(label, style: const pw.TextStyle(fontSize: 8, color: _muted)),
    ],
  );
  return pw.Wrap(
    spacing: 12,
    runSpacing: 4,
    children: [
      item(_primary, 'Nöbet (24 / 16B)'),
      if (data.dayShiftDays.isNotEmpty)
        item(_dayShiftTint, '7A gündüz mesaisi'),
      for (final type in data.leaves.keys)
        item(_leaveTint[type]!, '${type.shortLabel} = ${type.label}'),
      item(_weekendTint, 'Hafta sonu', border: _line),
      item(_holidayTint, 'Resmi tatil'),
    ],
  );
}

pw.Widget _shiftTable(PersonalRosterData data) {
  const header = pw.TextStyle(fontSize: 9, color: PdfColors.white);
  pw.Widget headerCell(String text) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 6),
    child: pw.Text(
      text,
      style: header.copyWith(fontWeight: pw.FontWeight.bold),
    ),
  );
  pw.Widget bodyCell(pw.Widget child) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
    child: child,
  );
  pw.Widget names(List<String> list, {String? highlight}) => pw.RichText(
    text: pw.TextSpan(
      children: [
        for (final (i, n) in list.indexed) ...[
          if (i > 0)
            const pw.TextSpan(
              text: ', ',
              style: pw.TextStyle(fontSize: 9, color: _ink),
            ),
          pw.TextSpan(
            text: n,
            style: pw.TextStyle(
              fontSize: 9,
              color: _ink,
              fontWeight: n == highlight ? pw.FontWeight.bold : null,
            ),
          ),
        ],
      ],
    ),
  );

  return pw.Table(
    columnWidths: const {
      0: pw.FixedColumnWidth(92),
      1: pw.FixedColumnWidth(42),
      2: pw.FlexColumnWidth(3),
      3: pw.FlexColumnWidth(2),
    },
    border: const pw.TableBorder(
      horizontalInside: pw.BorderSide(color: _line, width: 0.5),
    ),
    children: [
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: _primary),
        children: [
          headerCell('Tarih'),
          headerCell('Nöbet'),
          headerCell('Hemşireler'),
          headerCell('Radyoloji'),
        ],
      ),
      for (final (i, s) in data.shifts.indexed)
        pw.TableRow(
          decoration: pw.BoxDecoration(
            color: s.isWeekend
                ? _weekendTint
                : i.isOdd
                ? const PdfColor.fromInt(0xFFFAFAFA)
                : PdfColors.white,
          ),
          verticalAlignment: pw.TableCellVerticalAlignment.middle,
          children: [
            bodyCell(
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    formatDayMonth(s.day, data.month),
                    style: pw.TextStyle(
                      fontSize: 10,
                      fontWeight: pw.FontWeight.bold,
                      color: _ink,
                    ),
                  ),
                  pw.Text(
                    turkishWeekdayNames[DateTime(
                          data.year,
                          data.month,
                          s.day,
                        ).weekday -
                        1],
                    style: const pw.TextStyle(fontSize: 8, color: _muted),
                  ),
                ],
              ),
            ),
            bodyCell(
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(
                  horizontal: 5,
                  vertical: 2,
                ),
                decoration: const pw.BoxDecoration(
                  color: _primaryTint,
                  borderRadius: pw.BorderRadius.all(pw.Radius.circular(4)),
                ),
                child: pw.Text(
                  s.shift,
                  style: pw.TextStyle(
                    fontSize: 9,
                    fontWeight: pw.FontWeight.bold,
                    color: _primaryDark,
                  ),
                ),
              ),
            ),
            bodyCell(names(s.nurses, highlight: data.person.name)),
            bodyCell(
              s.techs.isEmpty
                  ? pw.Text(
                      '—',
                      style: const pw.TextStyle(fontSize: 9, color: _muted),
                    )
                  : names(s.techs, highlight: data.person.name),
            ),
          ],
        ),
    ],
  );
}

pw.Widget _notes(PersonalRosterData data) {
  final lines = <(String, String)>[
    if (data.dayShiftDays.isNotEmpty)
      (
        '7A gündüz mesaisi',
        '${data.dayShiftDays.join(', ')} ${turkishMonthNames[data.month - 1]}',
      ),
    for (final e in data.leaves.entries)
      (e.key.label, PersonalRoster.ranges(e.value, data.month)),
  ];
  return pw.Container(
    padding: const pw.EdgeInsets.all(10),
    decoration: pw.BoxDecoration(
      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
      border: pw.Border.all(color: _line, width: 0.5),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        for (final (label, value) in lines)
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 2),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.SizedBox(
                  width: 110,
                  child: pw.Text(
                    label,
                    style: pw.TextStyle(
                      fontSize: 9,
                      fontWeight: pw.FontWeight.bold,
                      color: _ink,
                    ),
                  ),
                ),
                pw.Expanded(
                  child: pw.Text(
                    value,
                    style: const pw.TextStyle(fontSize: 9, color: _ink),
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
  );
}
