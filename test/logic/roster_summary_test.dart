import 'package:flutter_test/flutter_test.dart';
import 'package:nobet_listesi/data/turkish_holidays.dart';
import 'package:nobet_listesi/logic/roster_summary.dart';
import 'package:nobet_listesi/models/models.dart';

void main() {
  final holidays = TurkishHolidays.forYear(2026);
  const settings = RosterSettings();

  // Ekim 2026: hafta sonu 3,4,10,11,17,18,24,25,31 + 29 (tatil).
  const people = [
    Person(id: 'a', name: 'Zeynep', role: Role.nurse),
    Person(id: 'b', name: 'Ayşe', role: Role.nurse),
    Person(id: 'c', name: 'Çiğdem', role: Role.nurse),
    Person(id: 't', name: 'Ali', role: Role.radiologyTech),
    Person(id: 'p', name: 'Pasif', role: Role.nurse, isActive: false),
    Person(id: 'q', name: 'Eski', role: Role.nurse, isActive: false),
  ];

  Map<int, DayAssignment> assignments() => {
    // Ayşe: 1-3 gün aşırı çift; 3, 10 hafta sonu; 29 tatil → 4 nöbet.
    1: const DayAssignment(day: 1, nurseIds: ['b', 'a'], techId: 't'),
    3: const DayAssignment(day: 3, nurseIds: ['b', 'q'], techId: 't'),
    10: const DayAssignment(day: 10, nurseIds: ['b', 'x'], techId: null),
    29: const DayAssignment(day: 29, nurseIds: ['b', 'a'], techId: 't'),
  };

  RosterSummary build() => RosterSummary.build(
    year: 2026,
    month: 10,
    assignments: assignments(),
    people: people,
    holidays: holidays,
    settings: settings,
  );

  test('kişi başı sayılar ve saatler', () {
    final s = build();
    expect(s.requiredHours, 145);

    final ayse = s.people.firstWhere((r) => r.personId == 'b');
    expect(ayse.name, 'Ayşe');
    expect(ayse.shifts, 4);
    expect(ayse.weekendShifts, 3); // 3, 10, 29
    expect(ayse.everyOtherDayPairs, 1); // 1-3
    expect(ayse.workedHours, 96);
    expect(ayse.requiredHours, 145);
    expect(ayse.overtimeHours, 0);
    expect(ayse.missingHours, 49);

    final ali = s.people.firstWhere((r) => r.personId == 't');
    expect(ali.shifts, 3);
    expect(ali.role, Role.radiologyTech);
  });

  test('fazla mesai: 7 nöbet → 168 − 145 = 23', () {
    final s = RosterSummary.build(
      year: 2026,
      month: 10,
      assignments: {
        for (final d in [1, 4, 7, 10, 13, 16, 19])
          d: DayAssignment(day: d, nurseIds: const ['a', 'b'], techId: 't'),
      },
      people: people,
      holidays: holidays,
      settings: settings,
    );
    final z = s.people.firstWhere((r) => r.personId == 'a');
    expect(z.workedHours, 168);
    expect(z.overtimeHours, 23);
    expect(z.missingHours, 0);
  });

  test('satırlar: aktifler (nöbetsiz de), nöbeti olan pasif ve silinmiş', () {
    final s = build();
    final ids = s.people.map((r) => r.personId).toList();
    // Hemşireler Türkçe sırayla, en sonda tekniker.
    expect(s.people.map((r) => r.name).toList(), [
      'Ayşe',
      'Çiğdem',
      'Eski',
      'Silinmiş kişi',
      'Zeynep',
      'Ali',
    ]);
    expect(ids, isNot(contains('p'))); // pasif ve nöbetsiz
    final cigdem = s.people.firstWhere((r) => r.personId == 'c');
    expect(cigdem.shifts, 0);
    final deleted = s.people.firstWhere((r) => r.personId == 'x');
    expect(deleted.role, Role.nurse);
  });

  test('rol grubu ortalamaları', () {
    final s = build();
    final nurses = s.averages[Role.nurse]!;
    // Ayşe 4, Çiğdem 0, Eski 1, Silinmiş 1, Zeynep 2 → 8 / 5.
    expect(nurses.people, 5);
    expect(nurses.shifts, 1.6);
    expect(nurses.workedHours, closeTo(1.6 * 24, 1e-9));
    final techs = s.averages[Role.radiologyTech]!;
    expect(techs.people, 1);
    expect(techs.shifts, 3);
    expect(techs.weekendShifts, 2); // 3, 29
    expect(techs.everyOtherDayPairs, 1);
  });

  test('boş liste: herkes 0, gereken saat yine hesaplanır', () {
    final s = RosterSummary.build(
      year: 2026,
      month: 11,
      assignments: const {},
      people: people,
      holidays: holidays,
      settings: settings,
    );
    expect(s.requiredHours, 147);
    expect(s.people.length, 4);
    expect(s.people.every((r) => r.shifts == 0), isTrue);
    expect(s.people.every((r) => r.missingHours == 147), isTrue);
  });
}
