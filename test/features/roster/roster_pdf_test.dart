import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:nobet_listesi/data/turkish_holidays.dart';
import 'package:nobet_listesi/features/roster/roster_pdf.dart';
import 'package:nobet_listesi/logic/roster_generator.dart';
import 'package:nobet_listesi/logic/roster_summary.dart';
import 'package:nobet_listesi/models/models.dart';
import 'package:pdf/widgets.dart' as pw;

const _names = [
  'Ayşe Yılmaz', 'Banu Kaya', 'Cemile Arslan', 'Derya Şahin', //
  'Elif Demir', 'Fatma Çelik', 'Gül Öztürk',
];
const _techs = ['Ali Koç', 'Burak Aydın', 'Can Yıldız', 'Deniz Kurt'];

void main() {
  setUpAll(() => initializeDateFormatting('tr_TR'));

  Future<List<int>> build({required bool singlePage}) async {
    final people = [
      for (var i = 0; i < _names.length; i++)
        Person(id: 'n$i', name: _names[i], role: Role.nurse),
      for (var i = 0; i < _techs.length; i++)
        Person(id: 't$i', name: _techs[i], role: Role.radiologyTech),
    ];
    final holidays = TurkishHolidays.forYear(2026);
    const settings = RosterSettings();
    final result = RosterGenerator(
      year: 2026,
      month: 10,
      people: people,
      holidays: holidays,
      seed: 3,
      attempts: 40,
    ).generate();
    final plan = MonthPlan(
      year: 2026,
      month: 10,
      assignments: result.assignments,
    );
    final summary = RosterSummary.build(
      year: 2026,
      month: 10,
      assignments: plan.assignments,
      people: people,
      holidays: holidays,
      settings: settings,
    );
    pw.Font font(String file) => pw.Font.ttf(
      File('assets/fonts/$file').readAsBytesSync().buffer.asByteData(),
    );
    return buildRosterPdf(
      plan: plan,
      rows: [
        for (final r in summary.people)
          (id: r.personId, name: r.name, role: r.role),
      ],
      summary: summary,
      weekendDays: RosterGenerator.weekendDays(2026, 10, holidays, settings),
      holidayDays: {29},
      shiftHours: 24,
      font: font('Roboto-Regular.ttf'),
      boldFont: font('Roboto-Bold.ttf'),
      missingByDay: const {},
      singlePage: singlePage,
    );
  }

  test('A4 yatay PDF ve tek sayfalık (görsel için) PDF üretilir', () async {
    for (final single in [false, true]) {
      final bytes = await build(singlePage: single);
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      expect(bytes.length, greaterThan(10000)); // gömülü font dahil
      final out = Platform.environment['NOBET_PDF_OUT'];
      if (out != null) {
        File('$out/liste${single ? '-tek' : ''}.pdf').writeAsBytesSync(bytes);
      }
    }
  });
}
