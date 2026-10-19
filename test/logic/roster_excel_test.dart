import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nobet_listesi/data/turkish_holidays.dart';
import 'package:nobet_listesi/logic/roster_excel.dart';
import 'package:nobet_listesi/logic/roster_generator.dart';
import 'package:nobet_listesi/logic/roster_summary.dart';
import 'package:nobet_listesi/models/models.dart';

void main() {
  final holidays = TurkishHolidays.forYear(2026);
  const settings = RosterSettings();
  final people = [
    for (var i = 1; i <= 7; i++)
      Person(id: 'n$i', name: 'Hemşire $i', role: Role.nurse),
    for (var i = 1; i <= 4; i++)
      Person(id: 't$i', name: 'Tekniker $i', role: Role.radiologyTech),
  ];

  ({List<int> bytes, MonthPlan plan, RosterSummary summary}) build() {
    final result = RosterGenerator(
      year: 2026,
      month: 10,
      people: people,
      holidays: holidays,
      settings: settings,
      seed: 1,
      attempts: 40,
      unavailableDays: const {
        'n1': [5, 6],
      },
    ).generate();
    final plan = MonthPlan(
      year: 2026,
      month: 10,
      assignments: result.assignments,
      annualLeave: const {
        'n1': [5, 6],
      },
    );
    final octHolidays = holidays.where((h) => h.date.month == 10).toList();
    final summary = RosterSummary.build(
      year: 2026,
      month: 10,
      assignments: plan.assignments,
      people: people,
      holidays: octHolidays,
      settings: settings,
      leaveDays: plan.leaveDays,
    );
    final bytes = RosterExcel.build(
      plan: plan,
      rows: [
        for (final r in summary.people)
          (id: r.personId, name: r.name, role: r.role),
      ],
      summary: summary,
      weekendDays: RosterGenerator.weekendDays(2026, 10, octHolidays, settings),
      holidayDays: {29},
      shiftHours: settings.shiftHours,
    );
    return (bytes: bytes, plan: plan, summary: summary);
  }

  test('iki sayfa: nöbet listesi ve mesai özeti', () {
    final (:bytes, :plan, :summary) = build();
    final files = {
      for (final f in ZipDecoder().decodeBytes(bytes))
        f.name: utf8.decode(f.content),
    };
    final workbook = files['xl/workbook.xml']!;
    expect(workbook, contains('name="Nöbet Listesi"'));
    expect(workbook, contains('name="Mesai Özeti"'));

    final roster = files['xl/worksheets/sheet1.xml']!;
    expect(roster, contains('Ekim 2026 Nöbet Listesi'));
    // Başlık: gün ve gün adı (1 Ekim 2026 Perşembe).
    expect(roster, contains('1\nPer'));
    expect(roster, contains('<mergeCell ref="A1:AF1"/>'));
    // 24 saatlik nöbetler sayı hücresi: her gün 2 hemşire + 1 tekniker.
    expect('<v>24</v>'.allMatches(roster).length, 31 * 3);
    // İzin kısaltması ve grup başlıkları.
    expect(roster, contains('>${LeaveType.annual.shortLabel}<'));
    expect(roster, contains('>Hemşireler<'));
    expect(roster, contains('>${Role.radiologyTech.pluralLabel}<'));

    final sheet2 = files['xl/worksheets/sheet2.xml']!;
    expect(sheet2, contains('Ekim 2026 Mesai Özeti'));
    expect(sheet2, contains('>Fazla mesai<'));
    final first = summary.people.first;
    expect(sheet2, contains('>${first.name}<'));
    expect(plan.assignments, hasLength(31));
  });

  // Elle denetim için: XLSX_OUT=yol flutter test ... dosyayı yazar.
  test('isteğe bağlı: dosyayı diske yaz', () {
    final out = Platform.environment['XLSX_OUT'];
    if (out == null) return;
    File(out).writeAsBytesSync(build().bytes);
  });
}
