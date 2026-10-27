import 'package:flutter_test/flutter_test.dart';
import 'package:nobet_listesi/data/turkish_holidays.dart';
import 'package:nobet_listesi/logic/roster_excel.dart';
import 'package:nobet_listesi/logic/roster_generator.dart';
import 'package:nobet_listesi/logic/roster_import.dart';
import 'package:nobet_listesi/logic/roster_summary.dart';
import 'package:nobet_listesi/logic/xlsx_reader.dart';
import 'package:nobet_listesi/models/models.dart';

void main() {
  final holidays = TurkishHolidays.forYear(2026);
  final people = [
    for (var i = 1; i <= 7; i++)
      Person(id: 'n$i', name: 'Hemşire $i', role: Role.nurse),
    for (var i = 1; i <= 4; i++)
      Person(id: 't$i', name: 'Tekniker $i', role: Role.radiologyTech),
    const Person(id: 'iy', name: 'İlknur Işık', role: Role.nurse),
  ];

  /// Uygulamanın Excel'e yazdığı listeyi okur.
  List<List<Object?>> exported(MonthPlan plan, RosterSettings settings) {
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
      holidayDays: const {29},
      shiftHours: 24,
      missingByDay: const {3: 1},
    );
    return XlsxReader.readSheet(bytes, preferredSheet: 'Nöbet Listesi');
  }

  Map<int, Set<String>> byDay(Map<int, DayAssignment> a) => {
    for (final e in a.entries) e.key: e.value.personIds.toSet(),
  };

  for (final techsPerDay in [1, 2]) {
    test('gidiş-dönüş: Excel\'e yazılan liste aynen geri okunur '
        '(günde $techsPerDay tekniker)', () {
      final settings = RosterSettings(techsPerDay: techsPerDay);
      final generated = RosterGenerator(
        year: 2026,
        month: 10,
        people: people,
        holidays: holidays,
        settings: settings,
        seed: 3,
        attempts: 30,
        unavailableDays: const {
          'n2': [5, 6, 7],
          't1': [12],
        },
      ).generate();
      final plan = MonthPlan(
        year: 2026,
        month: 10,
        assignments: generated.assignments,
        annualLeave: const {
          'n2': [5, 6, 7],
        },
        sickLeave: const {
          't1': [12],
        },
      );
      final r = RosterImport.fromRows(
        rows: exported(plan, settings),
        year: 2026,
        month: 10,
        people: people,
        techsPerDay: techsPerDay,
      );
      expect(r.warnings, isEmpty);
      expect(byDay(r.assignments), byDay(plan.assignments));
      for (final a in r.assignments.values) {
        expect(a.techId, plan.assignments[a.day]!.techId);
        expect(a.tech16bId, plan.assignments[a.day]!.tech16bId);
      }
      expect(r.leaves, {
        LeaveType.annual: {
          'n2': [5, 6, 7],
        },
        LeaveType.sick: {
          't1': [12],
        },
      });
      expect(r.hasTechShifts, isTrue);
      expect(
        r.shiftCount,
        plan.assignments.values.fold(0, (s, a) => s + a.personIds.length),
      );
    });
  }

  test('elle hazırlanmış tablo: isim eşleme, kodlar ve uyarılar', () {
    final r = RosterImport.fromRows(
      rows: [
        ['Ekim nöbetleri'],
        [],
        ['', 'Ad', for (var d = 1; d <= 31; d++) d],
        ['', '  ilknur  IŞIK ', 'x', null, '24', 'y.i.', 'İzin', '7A', '?'],
        ['', 'HEMŞİRE 1', '✓', 'nöbet'],
        ['', 'Tekniker 1', 24, '16B', 'Şua'],
        ['', 'Tekniker 2', '24'],
        ['', 'Bilinmeyen Kişi', 'X'],
        ['', 'Hemşireler'],
        ['', 'Hafta sonu'],
      ],
      year: 2026,
      month: 10,
      people: people,
    );
    expect(r.assignments, hasLength(31));
    expect(r.assignments[1]!.nurseIds, ['iy', 'n1']);
    expect(r.assignments[2]!.nurseIds, ['n1']);
    expect(r.assignments[3]!.nurseIds, ['iy']);
    // Günde bir teknikerde 16B, 24 sayılır.
    expect(r.assignments[1]!.techId, 't1');
    expect(r.assignments[2]!.techId, 't1');
    expect(r.leaves, {
      LeaveType.annual: {
        'iy': [4, 5],
      },
      LeaveType.radiation: {
        't1': [3],
      },
    });
    expect(r.matchedPeople, {'iy', 'n1', 't1', 't2'});
    expect(r.warnings, [
      '"Bilinmeyen Kişi" kişiler arasında yok; satırı atlandı (1 dolu hücre).',
      '1 hücre anlaşılamadı ve atlandı (ör. "?").',
      '1 Ekim: birden çok tekniker 24 nöbette; yalnız Tekniker 1 alındı.',
    ]);
  });

  test('gün sayısı ayla uyuşmazsa uyarı; başlık yoksa hata', () {
    final r = RosterImport.fromRows(
      rows: [
        ['Ad', for (var d = 1; d <= 30; d++) '$d\nGün'],
        ['Hemşire 1', 'X'],
      ],
      year: 2026,
      month: 10,
      people: people,
    );
    expect(
      r.warnings.single,
      'Dosyada 30 gün var; Ekim 31 gün. Eksik günler boş kaldı.',
    );
    expect(r.assignments[1]!.nurseIds, ['n1']);
    expect(r.assignments[31]!.personIds, isEmpty);

    expect(
      () => RosterImport.fromRows(
        rows: [
          ['Ad', 'Pzt', 'Sal'],
          ['Hemşire 1', 'X'],
        ],
        year: 2026,
        month: 10,
        people: people,
      ),
      throwsA(isA<RosterImportException>()),
    );
  });

  test('7A: teknikerde 7A günü olarak okunur, hemşirede yok sayılır', () {
    final r = RosterImport.fromRows(
      rows: [
        ['Ad', for (var d = 1; d <= 31; d++) d],
        ['Tekniker 1', '7A', '24', '7a'],
        ['Hemşire 1', '7A', 'X'],
      ],
      year: 2026,
      month: 10,
      people: people,
    );
    expect(r.techDayShifts, {
      't1': [1, 3],
    });
    expect(r.assignments[2]!.techId, 't1');
    expect(r.assignments[1]!.nurseIds, isEmpty);
    expect(r.assignments[2]!.nurseIds, ['n1']);
    expect(r.warnings, isEmpty);
  });
}
