import 'package:flutter_test/flutter_test.dart';
import 'package:nobet_listesi/logic/personal_roster.dart';
import 'package:nobet_listesi/logic/roster_calendar.dart';
import 'package:nobet_listesi/logic/roster_editor.dart';
import 'package:nobet_listesi/logic/roster_import.dart';
import 'package:nobet_listesi/logic/roster_summary.dart';
import 'package:nobet_listesi/models/models.dart';

/// 16A (16:00–08:00, hemşire ve tekniker): koltuk doldurur, 16 saat sayılır.
void main() {
  const people = [
    Person(id: 'a', name: 'Ayşe', role: Role.nurse),
    Person(id: 'b', name: 'Banu', role: Role.nurse),
    Person(id: 'c', name: 'Cemile', role: Role.nurse),
    Person(id: 't', name: 'Tarık', role: Role.radiologyTech),
    Person(id: 'u', name: 'Ufuk', role: Role.radiologyTech),
  ];
  const day3 = DayAssignment(day: 3, nurseIds: ['a', 'b'], shift16aIds: ['a']);

  test('vardiya kodu ve günden çıkan hemşirenin işareti düşer', () {
    expect(day3.shiftCode('a'), '16A');
    expect(day3.shiftCode('b'), '24');
    expect(day3.copyWith(nurseIds: ['b']).shift16aIds, isEmpty);
    expect(DayAssignment.fromJson(day3.toJson()), day3);
  });

  test('çalışılan saat: 16A 16, 24 tam', () {
    final s = RosterSummary.build(
      year: 2026,
      month: 11,
      assignments: const {3: day3},
      people: people,
      holidays: const [],
      settings: const RosterSettings(),
    );
    final a = s.people.firstWhere((p) => p.personId == 'a');
    final b = s.people.firstWhere((p) => p.personId == 'b');
    expect(a.shifts, 1);
    expect(a.workedHours, 16);
    expect(b.workedHours, 24);
  });

  test('yerine geçen 16A koltuğunu alır; çevirme', () {
    final replaced = RosterEditor.replace(
      const {3: day3},
      day: 3,
      role: Role.nurse,
      oldId: 'a',
      newId: 'c',
      nursesPerDay: 2,
    );
    expect(replaced[3]!.nurseIds, ['c', 'b']);
    expect(replaced[3]!.shift16aIds, ['c']);

    final toggled = RosterEditor.set16a(
      const {3: day3},
      day: 3,
      personId: 'b',
      night: true,
    );
    expect(toggled[3]!.shift16aIds, ['a', 'b']);
    expect(
      () => RosterEditor.set16a(
        const {3: day3},
        day: 3,
        personId: 'c',
        night: true,
      ),
      throwsA(isA<RosterEditException>()),
    );
  });

  test('takvim: 16:00 → ertesi 08:00, hatırlatma önceki akşam 20:00', () {
    final data = PersonalRoster.build(
      plan: const MonthPlan(year: 2026, month: 11, assignments: {3: day3}),
      person: people.first,
      people: people,
    );
    expect(data.shifts.single.shift, '16A');
    final e = RosterCalendar.events(data: data).single;
    expect(e.title, 'Nöbet (16A)');
    expect(e.start, DateTime(2026, 11, 3, 16));
    expect(e.end, DateTime(2026, 11, 4, 8));
    expect(RosterCalendar.reminderFor(e.start), const Duration(hours: 20));
  });

  test("Excel'den 16A okunur", () {
    final r = RosterImport.fromRows(
      rows: [
        ['', for (var d = 1; d <= 30; d++) d],
        ['Ayşe', '', '', '16A'],
        ['Banu', '', '', '24'],
      ],
      year: 2026,
      month: 11,
      people: people,
    );
    expect(r.assignments[3]!.nurseIds, ['a', 'b']);
    expect(r.assignments[3]!.shift16aIds, ['a']);
  });

  group('tekniker 16A', () {
    const day5 = DayAssignment(day: 5, techId: 't', shift16aIds: ['t']);

    test('vardiya kodu, saat, koltuktan çıkınca işaret düşer', () {
      expect(day5.shiftCode('t'), '16A');
      expect(day5.copyWith(clearTech: true).shift16aIds, isEmpty);
      final s = RosterSummary.build(
        year: 2026,
        month: 11,
        assignments: const {5: day5},
        people: people,
        holidays: const [],
        settings: const RosterSettings(),
      );
      expect(s.people.firstWhere((p) => p.personId == 't').workedHours, 16);
    });

    test('yerine geçen 16A alır; 16B\'ye geçince düşer; çevirme', () {
      final replaced = RosterEditor.replace(
        const {5: day5},
        day: 5,
        role: Role.radiologyTech,
        oldId: 't',
        newId: 'u',
        nursesPerDay: 2,
      );
      expect(replaced[5]!.techId, 'u');
      expect(replaced[5]!.shift16aIds, ['u']);

      final to16b = RosterEditor.setTechSeat(
        const {5: day5},
        day: 5,
        personId: 't',
        secondary: true,
      );
      expect(to16b[5]!.tech16bId, 't');
      expect(to16b[5]!.shift16aIds, isEmpty);

      final on = RosterEditor.set16a(
        const {5: DayAssignment(day: 5, techId: 'u')},
        day: 5,
        personId: 'u',
        night: true,
      );
      expect(on[5]!.shiftCode('u'), '16A');
      expect(
        () => RosterEditor.set16a(
          const {5: DayAssignment(day: 5, techId: 'u', tech16bId: 't')},
          day: 5,
          personId: 't',
          night: true,
        ),
        throwsA(isA<RosterEditException>()),
      );
    });

    test("Excel'den tekniker 16A okunur", () {
      final r = RosterImport.fromRows(
        rows: [
          ['', for (var d = 1; d <= 30; d++) d],
          ['Tarık', '', '', '', '', '16A'],
        ],
        year: 2026,
        month: 11,
        people: people,
      );
      expect(r.assignments[5]!.techId, 't');
      expect(r.assignments[5]!.shift16aIds, ['t']);
    });
  });
}
