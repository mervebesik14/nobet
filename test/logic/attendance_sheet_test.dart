import 'package:flutter_test/flutter_test.dart';
import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:nobet_listesi/logic/attendance_excel.dart';
import 'package:nobet_listesi/logic/attendance_sheet.dart';
import 'package:nobet_listesi/logic/day_shift_planner.dart';
import 'package:nobet_listesi/models/models.dart';

void main() {
  test('nöbet 24, hafta içi boş N.İ., hafta sonu boş, izin ve 7A', () {
    // Kasım 2026: 1 Pazar, 2 Pazartesi, 7–8 hafta sonu.
    const people = [
      Person(id: 'a', name: 'Ayşe', role: Role.nurse),
      Person(id: 't', name: 'Ali', role: Role.radiologyTech),
    ];
    final plan = MonthPlan(
      year: 2026,
      month: 11,
      assignments: const {
        2: DayAssignment(
          day: 2,
          nurseIds: ['a'],
          techId: 't',
          shift16aIds: ['t'],
        ),
        7: DayAssignment(day: 7, nurseIds: ['a']),
        10: DayAssignment(day: 10, extraShifts: {'a': '4A'}),
        11: DayAssignment(day: 11, nurseIds: ['a'], extraShifts: {}),
      },
      annualLeave: const {
        'a': [4, 5],
      },
      sickLeave: const {
        't': [8, 9],
      },
    );
    final rows = AttendanceSheet.build(
      plan: plan,
      rows: const [
        (id: 'a', name: 'Ayşe', role: Role.nurse),
        (id: 't', name: 'Ali', role: Role.radiologyTech),
      ],
      people: people,
      closedDays: const {1, 7, 8, 14, 15, 21, 22, 28, 29},
      dayShifts: const [
        DayShift(day: 3, personId: 'a', hours: 7, isSubstitute: true),
      ],
    );
    final a = rows.first.codes;
    expect(a[0], ''); // 1 Pazar
    expect(a[1], '24');
    expect(a[2], '7A');
    expect(a[3], 'Y.İ.');
    expect(a[5], 'N.İ.'); // 6 Cuma
    expect(a[6], '24'); // 7 Cumartesi nöbet
    expect(a[7], ''); // 8 Pazar
    expect(a[9], '4A');
    expect(rows.first.shifts, 3);
    expect(rows.first.dayShifts, 1);
    expect(rows.first.leaveDays, 2);
    expect(rows.first.title, 'Hemşire');

    final t = rows.last.codes;
    expect(t[1], '16A');
    expect(t[7], 'R.'); // izin hafta sonu da yazılır
    expect(t[8], 'R.');
    expect(rows.last.title, 'Radyoloji Teknikeri');
    expect(
      AttendanceSheet.legend(),
      contains('N.İ. = nöbet izni (hafta içi çalışmadığı gün)'),
    );
  });
  test('Excel: başlık, kodlar ve toplamlar', () {
    final bytes = AttendanceExcel.build(
      year: 2026,
      month: 11,
      rows: [
        (
          personId: 'a',
          name: 'Ayşe',
          title: 'Hemşire',
          codes: [for (var d = 1; d <= 30; d++) d == 2 ? '24' : 'N.İ.'],
          shifts: 1,
          dayShifts: 0,
          offDays: 29,
          leaveDays: 0,
        ),
      ],
      closedDays: const {1},
      workedHours: const {'a': 24},
      institution: 'Örnek Hastanesi',
    );
    final sheet = ZipDecoder()
        .decodeBytes(bytes)
        .firstWhere((f) => f.name == 'xl/worksheets/sheet1.xml');
    final xml = utf8.decode(sheet.content);
    expect(xml, contains('Kasım 2026 Puantaj Cetveli'));
    expect(xml, contains('Örnek Hastanesi'));
    expect(xml, contains('N.İ.'));
    expect(xml, contains('Ayşe'));
  });
}
