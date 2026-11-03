import 'package:flutter_test/flutter_test.dart';
import 'package:nobet_listesi/logic/day_shift_planner.dart';
import 'package:nobet_listesi/logic/personal_roster.dart';
import 'package:nobet_listesi/logic/roster_calendar.dart';
import 'package:nobet_listesi/logic/roster_editor.dart';
import 'package:nobet_listesi/logic/roster_import.dart';
import 'package:nobet_listesi/logic/roster_summary.dart';
import 'package:nobet_listesi/logic/shift_reminder.dart';
import 'package:nobet_listesi/models/models.dart';

/// Özel mesailer: koltuk dolduran (19A) ve ek mesai (G).
void main() {
  const s19 = CustomShift(code: '19A', startMinute: 13 * 60, hours: 19);
  const g = CustomShift(
    code: 'G',
    startMinute: 9 * 60,
    hours: 6,
    fillsSeat: false,
  );
  const settings = RosterSettings(customShifts: [s19, g]);
  const people = [
    Person(id: 'a', name: 'Ayşe', role: Role.nurse),
    Person(id: 'b', name: 'Banu', role: Role.nurse),
    Person(id: 'c', name: 'Cemile', role: Role.nurse),
    Person(id: 't', name: 'Tarık', role: Role.radiologyTech),
  ];
  const day3 = DayAssignment(
    day: 3,
    nurseIds: ['a', 'b'],
    techId: 't',
    customShifts: {'a': '19A'},
    extraShifts: {'c': 'G'},
  );

  test('vardiya kodu, ek mesai, JSON', () {
    expect(day3.shiftCode('a'), '19A');
    expect(day3.shiftCode('b'), '24');
    expect(day3.extraShiftOf('c'), 'G');
    expect(day3.extraShiftOf('a'), isNull);
    expect(day3.personIds, isNot(contains('c')));
    expect(DayAssignment.fromJson(day3.toJson()), day3);
    // Koltuktan çıkanın özel mesaisi, koltuğa girenin ek mesaisi düşer.
    final moved = day3.copyWith(nurseIds: ['b', 'c']);
    expect(moved.customShifts, isEmpty);
    expect(moved.extraShifts, isEmpty);
  });

  test('çalışılan saat: koltuktaki 19A 19, ek G 6', () {
    final s = RosterSummary.build(
      year: 2026,
      month: 11,
      assignments: const {3: day3},
      people: people,
      holidays: const [],
      settings: settings,
    );
    double hours(String id) =>
        s.people.firstWhere((p) => p.personId == id).workedHours;
    expect(hours('a'), 19);
    expect(hours('b'), 24);
    expect(hours('c'), 6);
    expect(s.people.firstWhere((p) => p.personId == 'c').shifts, 0);
  });

  test('geldiği gün: nöbet, 7A ve ek mesai günleri bir kez sayılır', () {
    final s = RosterSummary.build(
      year: 2026,
      month: 11,
      assignments: const {
        3: day3,
        4: DayAssignment(day: 4, nurseIds: ['b', 'c'], techId: 't'),
      },
      people: people,
      holidays: const [],
      settings: settings,
      // Ayşe 5'inde 7A; Banu nöbetli olduğu 3'ünde de 7A (tek gün).
      dayShifts: const [
        DayShift(day: 5, personId: 'a', hours: 7, isSubstitute: false),
        DayShift(day: 3, personId: 'b', hours: 7, isSubstitute: false),
      ],
    );
    int days(String id) =>
        s.people.firstWhere((p) => p.personId == id).attendedDays;
    expect(days('a'), 2); // 3 (19A) + 5 (7A)
    expect(days('b'), 2); // 3, 4
    expect(days('c'), 2); // 3 (ek G) + 4
    expect(days('t'), 2);
  });

  test(
    'düzenleme: çevir, yerine geçen alır, ek mesai, 16A ile birlikte olmaz',
    () {
      final to19 = RosterEditor.setCustomShift(
        const {3: day3},
        day: 3,
        personId: 't',
        code: '19A',
      );
      expect(to19[3]!.shiftCode('t'), '19A');
      final back = RosterEditor.setCustomShift(
        to19,
        day: 3,
        personId: 't',
        code: null,
      );
      expect(back[3]!.shiftCode('t'), '24');

      final replaced = RosterEditor.replace(
        const {3: day3},
        day: 3,
        role: Role.nurse,
        oldId: 'a',
        newId: 'c',
        nursesPerDay: 2,
      );
      expect(replaced[3]!.shiftCode('c'), '19A');
      expect(replaced[3]!.extraShifts, isEmpty);

      final night = RosterEditor.set16a(
        const {3: day3},
        day: 3,
        personId: 'a',
        night: true,
      );
      expect(night[3]!.shiftCode('a'), '16A');
      expect(night[3]!.customShifts, isEmpty);

      final extra = RosterEditor.setExtraShift(
        const {3: day3},
        day: 3,
        personId: 'c',
        code: null,
      );
      expect(extra[3]!.extraShifts, isEmpty);
      expect(
        () => RosterEditor.setExtraShift(
          const {3: day3},
          day: 3,
          personId: 'a',
          code: 'G',
        ),
        throwsA(isA<RosterEditException>()),
      );
    },
  );

  test('takvim ve kişisel liste: başlangıç ve süre tanımdan', () {
    const plan = MonthPlan(year: 2026, month: 11, assignments: {3: day3});
    final a = PersonalRoster.build(
      plan: plan,
      person: people[0],
      people: people,
    );
    expect(a.shifts.single.shift, '19A');
    final e = RosterCalendar.events(
      data: a,
      customShifts: settings.customShifts,
    ).single;
    expect(e.start, DateTime(2026, 11, 3, 13));
    expect(e.end, DateTime(2026, 11, 4, 8));
    expect(e.title, 'Nöbet (19A)');

    final c = PersonalRoster.build(
      plan: plan,
      person: people[2],
      people: people,
    );
    expect(c.shifts.single.isExtra, isTrue);
    expect(c.weekendShifts, 0);
    final ec = RosterCalendar.events(
      data: c,
      customShifts: settings.customShifts,
    ).single;
    expect(ec.start, DateTime(2026, 11, 3, 9));
    expect(ec.end, DateTime(2026, 11, 3, 15));
    expect(ec.title, 'G');

    final reminders = ShiftReminder.upcoming(
      now: DateTime(2026, 11, 1),
      plans: [plan],
      personId: 'c',
    );
    expect(reminders.single.shift, 'G');
  });

  test("Excel'den özel mesai okunur", () {
    final r = RosterImport.fromRows(
      rows: [
        ['', for (var d = 1; d <= 30; d++) d],
        ['Ayşe', '', '', '19a'],
        ['Banu', '', '', '24'],
        ['Cemile', '', '', 'G'],
        ['Tarık', '', '', '24'],
      ],
      year: 2026,
      month: 11,
      people: people,
      customShifts: settings.customShifts,
    );
    final a = r.assignments[3]!;
    expect(a.nurseIds, ['a', 'b']);
    expect(a.customShifts, {'a': '19A'});
    expect(a.extraShifts, {'c': 'G'});
  });
}
