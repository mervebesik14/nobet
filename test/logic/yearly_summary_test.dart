import 'package:flutter_test/flutter_test.dart';
import 'package:nobet_listesi/data/turkish_holidays.dart';
import 'package:nobet_listesi/logic/person_totals.dart';
import 'package:nobet_listesi/logic/yearly_summary.dart';
import 'package:nobet_listesi/models/models.dart';

void main() {
  final holidays = TurkishHolidays.forYear(2026);
  const people = [
    Person(id: 'a', name: 'Zeynep', role: Role.nurse),
    Person(id: 'b', name: 'Ayşe', role: Role.nurse),
    Person(id: 't', name: 'Ali', role: Role.radiologyTech),
  ];

  MonthPlan plan(int month, Map<int, List<String>> nurses, String tech) =>
      MonthPlan(
        year: 2026,
        month: month,
        assignments: {
          for (final e in nurses.entries)
            e.key: DayAssignment(day: e.key, nurseIds: e.value, techId: tech),
        },
      );

  final plans = [
    // Eylül 2026: gereken 22 × 7 = 154. Ayşe 1, 3 (çift), 5 → zincir değil
    // ama 1-3 ve 3-5 iki çift; Zeynep 2.
    plan(9, {
      1: ['b'],
      2: ['a'],
      3: ['b'],
      5: ['b'],
    }, 't'),
    // Ekim 2026: Ayşe 4 (Paz) ve 10 (Cmt) hafta sonu.
    plan(10, {
      4: ['b'],
      10: ['b', 'a'],
    }, 't'),
    // Kasım: liste yok → sayılmaz.
    const MonthPlan(year: 2026, month: 11),
    // Başka yıl → sayılmaz.
    MonthPlan(
      year: 2025,
      month: 12,
      assignments: {
        1: const DayAssignment(day: 1, nurseIds: ['b'], techId: 't'),
      },
    ),
  ];

  YearlySummary build({int? beforeMonth}) => YearlySummary.build(
    year: 2026,
    plans: plans,
    people: people,
    holidays: holidays,
    settings: const RosterSettings(),
    beforeMonth: beforeMonth,
  );

  test('yalnız o yılın listesi olan ayları toplar', () {
    final s = build();
    expect(s.months, [9, 10]);
    final ayse = s.byId['b']!;
    expect(ayse.shifts, 5);
    expect(ayse.weekendShifts, 3); // 5 Eylül (Cmt), 4 ve 10 Ekim
    expect(ayse.everyOtherDayPairs, 2); // 1-3, 3-5 Eylül
    expect(ayse.workedHours, 120);
    expect(ayse.requiredHours, 154 + 145);
    expect(ayse.months, 2);
    expect(s.byId['t']!.shifts, 6);
  });

  test('rol ortalaması (yıllık toplam)', () {
    final s = build();
    // Ayşe 5, Zeynep 2 nöbet.
    expect(s.roleMean(Role.nurse, (t) => t.shifts), 3.5);
    expect(s.roleMean(Role.radiologyTech, (t) => t.shifts), 6);
  });

  test('fazla mesai ay ay toplanır', () {
    // Ali: Eylül 4 nöbet (96 < 154), Ekim 2 nöbet → fazla mesai 0.
    expect(build().byId['t']!.overtimeHours, 0);
    const a = PersonTotals(overtimeHours: 23, shifts: 7, months: 1);
    const b = PersonTotals(overtimeHours: 10, shifts: 7, months: 1);
    final sum = a + b;
    expect(sum.overtimeHours, 33);
    expect(sum.shifts, 14);
    expect(sum.months, 2);
  });

  test('beforeMonth ile yalnız önceki aylar', () {
    final s = build(beforeMonth: 10);
    expect(s.months, [9]);
    expect(s.byId['b']!.shifts, 3);
  });

  test('satır sırası: rol, sonra Türkçe ad', () {
    expect(build().rows.map((r) => r.name), ['Ayşe', 'Zeynep', 'Ali']);
  });

  test('aylık kırılım ve rol ortalamasından fark', () {
    final s = build();
    final ayse = s.rows.firstWhere((r) => r.personId == 'b');
    final zeynep = s.rows.firstWhere((r) => r.personId == 'a');
    // Eylül: Ayşe 3, Zeynep 1 → ortalama 2. Ekim: Ayşe 2, Zeynep 1.
    expect(ayse.byMonth.keys, [9, 10]);
    expect(ayse.byMonth[9]!.shifts, 3);
    expect(zeynep.byMonth[10]!.shifts, 1);
    expect(s.deviation(ayse, 9, (t) => t.shifts), 1);
    expect(s.deviation(zeynep, 9, (t) => t.shifts), -1);
    expect(s.deviation(ayse, 10, (t) => t.shifts), 0.5);
    // Tek tekniker: farkı 0.
    final ali = s.rows.firstWhere((r) => r.personId == 't');
    expect(s.deviation(ali, 9, (t) => t.shifts), 0);
    // Kaydı olmayan ay.
    expect(s.deviation(ayse, 11, (t) => t.shifts), isNull);
    // Toplam = ayların toplamı.
    expect(ayse.totals.shifts, 5);
  });

  test('çalışabildiği gün: izin ve işe başlamadan önceki günler düşülür', () {
    final s = YearlySummary.build(
      year: 2026,
      plans: [
        MonthPlan(
          year: 2026,
          month: 10,
          assignments: {
            20: const DayAssignment(day: 20, nurseIds: ['n'], techId: 't'),
            22: const DayAssignment(day: 22, nurseIds: ['b'], techId: 't'),
          },
          annualLeave: const {
            'b': [1, 2, 3],
          },
        ),
      ],
      people: [
        ...people,
        Person(
          id: 'n',
          name: 'Nur',
          role: Role.nurse,
          startDate: DateTime(2026, 10, 16),
        ),
      ],
      holidays: holidays,
      settings: const RosterSettings(),
    );
    expect(s.byId['a']!.availableDays, 31);
    expect(s.byId['b']!.availableDays, 28); // 3 gün izin
    expect(s.byId['n']!.availableDays, 16); // 16–31 Ekim
  });

  test('7A günleri ay ay toplanır', () {
    // Eylül 2026: 7 (Pzt) ve 8 Eylül teknikere elle 7A; Ekim'de 6 Ekim.
    final s = YearlySummary.build(
      year: 2026,
      plans: [
        plans[0].copyWith(
          techDayShifts: const {
            't': [7, 8],
          },
        ),
        plans[1].copyWith(
          techDayShifts: const {
            't': [6],
          },
        ),
      ],
      people: people,
      holidays: holidays,
      settings: const RosterSettings(),
    );
    expect(s.byId['t']!.dayShifts, 3);
    expect(
      s.rows.firstWhere((r) => r.personId == 't').byMonth[9]!.dayShifts,
      2,
    );
    expect(s.byId['b']!.dayShifts, 0);
  });

  test('gün aşırı zincirler ay ay tutulur ve toplanır', () {
    final s = YearlySummary.build(
      year: 2026,
      plans: [
        // Eylül: Ayşe 1-3-5-7 (4'lü); Ekim: 10-12 (2'li) ve 20-22-24 (3'lü).
        plan(9, {
          1: ['b'],
          3: ['b'],
          5: ['b'],
          7: ['b'],
        }, 't'),
        plan(10, {
          10: ['b'],
          12: ['b'],
          20: ['b'],
          22: ['b'],
          24: ['b'],
        }, 't'),
      ],
      people: people,
      holidays: holidays,
      settings: const RosterSettings(),
    );
    final b = s.byId['b']!;
    expect(b.everyOtherDayDays, 9);
    expect(b.longestChain, 4);
    expect(b.chainCounts, {2: 1, 3: 1, 4: 1});
    expect(b.chainSummary, "2'li × 1 · 3'lü × 1 · 4'lü × 1");
    final row = s.rows.firstWhere((r) => r.personId == 'b');
    expect(row.byMonth[9]!.everyOtherDayChains, [
      [1, 3, 5, 7],
    ]);
    expect(row.byMonth[10]!.everyOtherDayChains, [
      [10, 12],
      [20, 22, 24],
    ]);
  });
}
