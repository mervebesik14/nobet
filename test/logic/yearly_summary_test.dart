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
}
