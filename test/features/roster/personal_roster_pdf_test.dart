import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:nobet_listesi/features/roster/personal_roster_pdf.dart';
import 'package:nobet_listesi/logic/day_shift_planner.dart';
import 'package:nobet_listesi/logic/personal_roster.dart';
import 'package:nobet_listesi/models/models.dart';

import '../../helpers.dart';

void main() {
  setUpAll(() => initializeDateFormatting('tr_TR'));

  test('kişiye özel PDF üretilir (takvim, ekip, izin, 7A)', () async {
    const people = [
      Person(
        id: 'a',
        name: 'Merve Beşik',
        role: Role.nurse,
        isChargeNurse: true,
      ),
      Person(id: 'b', name: 'Banu', role: Role.nurse),
      Person(id: 'm', name: 'Mehmet', role: Role.radiologyTech),
    ];
    const plan = MonthPlan(
      year: 2026,
      month: 10,
      assignments: {
        3: DayAssignment(day: 3, nurseIds: ['a', 'b'], techId: 'm'),
        15: DayAssignment(day: 15, nurseIds: ['a', 'b'], techId: 'm'),
      },
      annualLeave: {
        'a': [20, 21, 22],
      },
      sickLeave: {
        'a': [27],
      },
    );
    final fonts = await FakePlatformServices().loadPdfFonts();
    final bytes = await buildPersonalRosterPdf(
      data: PersonalRoster.build(
        plan: plan,
        person: people.first,
        people: people,
        dayShifts: const [
          DayShift(day: 1, personId: 'a', hours: 7, isSubstitute: false),
          DayShift(day: 2, personId: 'a', hours: 7, isSubstitute: false),
        ],
        weekendDays: const {3, 4, 10, 11, 17, 18, 24, 25, 29, 31},
      ),
      weekendDays: const {3, 4, 10, 11, 17, 18, 24, 25, 29, 31},
      holidayDays: const {29},
      font: fonts.regular,
      boldFont: fonts.bold,
      createdAt: DateTime(2026, 10, 14),
    );
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    final out = Platform.environment['PERSONAL_PDF_OUT'];
    if (out != null) File(out).writeAsBytesSync(bytes);
  });
}
