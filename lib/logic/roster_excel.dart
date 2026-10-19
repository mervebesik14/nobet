import 'dart:typed_data';

import '../models/models.dart';
import 'day_shift_planner.dart';
import 'roster_summary.dart';
import 'turkish_dates.dart';
import 'xlsx_writer.dart';

/// Nöbet listesini Excel'e döker (saf Dart): "Nöbet Listesi" sayfası PDF'teki
/// tablonun aynısı (renkli hafta sonu, tatil, izin), "Mesai Özeti" sayfası
/// kişi başı sayılar. Sayılar gerçek sayı hücresidir; idare ya da bordro
/// için toplanabilir.
class RosterExcel {
  const RosterExcel._();

  static const _weekend = 0xE3ECEB;
  static const _holiday = 0xF6E1C4;
  static const _group = 0xB9E9E1;
  static const _missing = 0xF9D6D2;
  static const _header = 0xEEEEEE;
  static const _dayShift = 0xF5E3C8;
  static const _leave = {
    LeaveType.annual: 0xCADEE2,
    LeaveType.radiation: 0xDDD2EE,
    LeaveType.sick: 0xF6D5E1,
  };

  static const _weekdays = ['Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz'];

  static Uint8List build({
    required MonthPlan plan,
    required List<({String id, String name, Role role})> rows,
    required RosterSummary summary,
    required Set<int> weekendDays,
    required Set<int> holidayDays,
    required int shiftHours,
    Map<int, int> missingByDay = const {},
    Map<int, DayShift> dayShifts = const {},
  }) => XlsxWriter.build([
    _rosterSheet(
      plan: plan,
      rows: rows,
      weekendDays: weekendDays,
      holidayDays: holidayDays,
      shiftHours: shiftHours,
      missingByDay: missingByDay,
      dayShifts: dayShifts,
    ),
    _summarySheet(plan, summary),
  ]);

  static String title(MonthPlan plan) =>
      '${turkishMonthNames[plan.month - 1]} ${plan.year} Nöbet Listesi';

  static XlsxSheet _rosterSheet({
    required MonthPlan plan,
    required List<({String id, String name, Role role})> rows,
    required Set<int> weekendDays,
    required Set<int> holidayDays,
    required int shiftHours,
    required Map<int, int> missingByDay,
    required Map<int, DayShift> dayShifts,
  }) {
    final days = [for (var d = 1; d <= plan.daysInMonth; d++) d];
    int? columnFill(int d) => holidayDays.contains(d)
        ? _holiday
        : weekendDays.contains(d)
        ? _weekend
        : null;
    const center = XlsxStyle(align: XlsxAlign.center);
    const bold = XlsxStyle(bold: true);
    XlsxCell dayCell(Object? v, int d, {int? fill, bool strong = false}) =>
        XlsxCell(
          v,
          style: center.copyWith(fill: fill ?? columnFill(d), bold: strong),
        );

    final worked = <String, Set<int>>{};
    for (final a in plan.assignments.values) {
      for (final id in a.personIds) {
        (worked[id] ??= {}).add(a.day);
      }
    }

    final out = <List<XlsxCell>>[
      [
        XlsxCell(
          title(plan),
          style: const XlsxStyle(bold: true, border: false),
        ),
      ],
      [
        const XlsxCell('Ad Soyad', style: XlsxStyle(bold: true, fill: _header)),
        for (final d in days)
          XlsxCell(
            '$d\n${_weekdays[DateTime(plan.year, plan.month, d).weekday - 1]}',
            style: XlsxStyle(
              bold: true,
              align: XlsxAlign.center,
              wrap: true,
              fill: columnFill(d) ?? _header,
            ),
          ),
      ],
    ];

    Role? currentRole;
    for (final row in rows) {
      if (row.role != currentRole) {
        currentRole = row.role;
        out.add([
          XlsxCell(row.role.pluralLabel, style: bold.copyWith(fill: _group)),
          for (final _ in days)
            const XlsxCell.empty(style: XlsxStyle(fill: _group)),
        ]);
      }
      final personDays = worked[row.id] ?? const <int>{};
      final leaveOn = <int, LeaveType>{
        for (final type in LeaveType.values.reversed)
          for (final d in plan.leaveOf(row.id, type)) d: type,
      };
      out.add([
        XlsxCell(row.name),
        for (final d in days)
          if (personDays.contains(d))
            (plan.assignments[d]?.isSecondaryTech(row.id) ?? false)
                ? dayCell('16B', d, strong: true)
                : dayCell(shiftHours, d, strong: true)
          else if (dayShifts[d]?.personId == row.id)
            dayCell('7A', d, fill: _dayShift, strong: true)
          else if (leaveOn[d] case final type?)
            dayCell(type.shortLabel, d, fill: _leave[type], strong: true)
          else
            dayCell(null, d),
      ]);
    }
    if (missingByDay.isNotEmpty) {
      out.add([
        const XlsxCell('Eksik', style: XlsxStyle(fill: _missing)),
        for (final d in days)
          missingByDay.containsKey(d)
              ? dayCell(missingByDay[d], d, fill: _missing)
              : dayCell(null, d),
      ]);
    }

    // Açıklama.
    out.add(const []);
    XlsxCell legend(int fill, String label) =>
        XlsxCell(label, style: XlsxStyle(fill: fill));
    out
      ..add([legend(_weekend, 'Hafta sonu')])
      ..add([legend(_holiday, 'Resmi tatil')]);
    for (final type in LeaveType.values) {
      out.add([legend(_leave[type]!, '${type.shortLabel} = ${type.label}')]);
    }
    if (dayShifts.isNotEmpty) {
      out.add([legend(_dayShift, '7A = Gündüz mesaisi')]);
    }

    return XlsxSheet(
      'Nöbet Listesi',
      rows: out,
      columnWidths: {0: 24, for (var i = 1; i <= days.length; i++) i: 5},
      rowHeights: const {1: 28},
      freezeRows: 2,
      freezeColumns: 1,
      printLandscape: true,
      merges: ['A1:${XlsxWriter.columnName(days.length)}1'],
    );
  }

  static double _round(double v) => (v * 10).roundToDouble() / 10;

  static XlsxSheet _summarySheet(MonthPlan plan, RosterSummary summary) {
    final has7A = summary.people.any((r) => r.dayShifts > 0);
    final hasNational = summary.people.any((r) => r.nationalHolidayShifts > 0);
    final hasReligious = summary.people.any(
      (r) => r.religiousHolidayShifts > 0,
    );
    const head = XlsxStyle(bold: true, fill: _header, wrap: true);
    const number = XlsxStyle(align: XlsxAlign.right);
    XlsxCell n(num v) => XlsxCell(v is double ? _round(v) : v, style: number);

    final headers = [
      'Ad Soyad',
      'Görev',
      'Toplam nöbet',
      'Hafta sonu nöbet',
      if (hasNational) 'Resmi tatil nöbeti',
      if (hasReligious) 'Dini bayram nöbeti',
      'Gün aşırı çift',
      '4–5 gün ara',
      if (has7A) '7A gün',
      'Çalışılan saat',
      'Gereken saat',
      'Fazla mesai',
    ];
    final out = <List<XlsxCell>>[
      [
        XlsxCell(
          '${turkishMonthNames[plan.month - 1]} ${plan.year} Mesai Özeti',
          style: const XlsxStyle(bold: true, border: false),
        ),
      ],
      [for (final h in headers) XlsxCell(h, style: head)],
      for (final r in summary.people)
        [
          XlsxCell(r.name),
          XlsxCell(r.isChargeNurse ? 'Sorumlu hemşire' : r.role.label),
          n(r.shifts),
          n(r.weekendShifts),
          if (hasNational) n(r.nationalHolidayShifts),
          if (hasReligious) n(r.religiousHolidayShifts),
          n(r.everyOtherDayPairs),
          n(r.longGaps),
          if (has7A) n(r.dayShifts),
          n(r.workedHours),
          n(r.requiredHours),
          n(r.overtimeHours),
        ],
      for (final a in summary.averages.values)
        [
          const XlsxCell('Ortalama', style: XlsxStyle(bold: true)),
          XlsxCell(a.role.pluralLabel, style: const XlsxStyle(bold: true)),
          n(a.shifts),
          n(a.weekendShifts),
          if (hasNational) n(a.nationalHolidayShifts),
          if (hasReligious) n(a.religiousHolidayShifts),
          n(a.everyOtherDayPairs),
          const XlsxCell.empty(),
          if (has7A) const XlsxCell.empty(),
          n(a.workedHours),
          n(summary.requiredHours),
          n(a.overtimeHours),
        ],
    ];
    return XlsxSheet(
      'Mesai Özeti',
      rows: out,
      columnWidths: {
        0: 24,
        1: 22,
        for (var i = 2; i < headers.length; i++) i: 11,
      },
      rowHeights: const {1: 30},
      freezeRows: 2,
      freezeColumns: 1,
      printLandscape: true,
      merges: ['A1:${XlsxWriter.columnName(headers.length - 1)}1'],
    );
  }
}
