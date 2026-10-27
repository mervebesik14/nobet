import 'package:flutter_test/flutter_test.dart';
import 'package:nobet_listesi/logic/day_shift_planner.dart';
import 'package:nobet_listesi/logic/personal_roster.dart';
import 'package:nobet_listesi/models/models.dart';

void main() {
  const people = [
    Person(id: 'a', name: 'Ayşe', role: Role.nurse),
    Person(id: 'b', name: 'Banu', role: Role.nurse),
    Person(id: 'c', name: 'Cemile', role: Role.nurse),
    Person(id: 'm', name: 'Mehmet', role: Role.radiologyTech),
    Person(id: 'z', name: 'Zeynep', role: Role.radiologyTech),
  ];

  // Ekim 2026: 3 Cumartesi, 7 Çarşamba.
  const plan = MonthPlan(
    year: 2026,
    month: 10,
    assignments: {
      3: DayAssignment(day: 3, nurseIds: ['a', 'b'], techId: 'm'),
      5: DayAssignment(day: 5, nurseIds: ['b', 'c'], techId: 'z'),
      7: DayAssignment(
        day: 7,
        nurseIds: ['c', 'a'],
        techId: 'z',
        tech16bId: 'm',
      ),
    },
    annualLeave: {
      'a': [12, 13, 14, 20],
    },
  );

  test('nöbet günleri, o günün tüm nöbetçileri, izin ve toplam', () {
    final text = PersonalRoster.text(
      plan: plan,
      person: people.first,
      people: people,
      dayShifts: const [
        DayShift(day: 9, personId: 'a', hours: 7, isSubstitute: true),
      ],
    );
    expect(
      text,
      'Ayşe · Ekim 2026 nöbetleri\n'
      '\n'
      '• 3 Ekim Cumartesi — 24\n'
      '  Hemşire: Ayşe, Banu\n'
      '  Radyoloji: Mehmet\n'
      '• 7 Ekim Çarşamba — 24\n'
      '  Hemşire: Cemile, Ayşe\n'
      '  Radyoloji: Zeynep (24), Mehmet (16B)\n'
      '\n'
      '7A (gündüz): 9 Ekim\n'
      '\n'
      'Yıllık izin: 12–14, 20 Ekim\n'
      '\n'
      'Toplam: 2 nöbet',
    );
  });

  test('16B teknikerinin kendi nöbeti 16B yazar', () {
    final text = PersonalRoster.text(
      plan: plan,
      person: people[3],
      people: people,
    );
    expect(text, contains('• 7 Ekim Çarşamba — 16B'));
    expect(text, contains('• 3 Ekim Cumartesi — 24'));
    expect(text, endsWith('Toplam: 2 nöbet'));
  });

  test('nöbeti yoksa belirtir; silinmiş kişi adı', () {
    const p = Person(id: 'x', name: 'Yeni', role: Role.nurse);
    final text = PersonalRoster.text(plan: plan, person: p, people: people);
    expect(text, contains('Bu ay nöbet yok.'));
    expect(text, endsWith('Toplam: 0 nöbet'));

    final missing = PersonalRoster.text(
      plan: plan,
      person: people[1],
      people: people.where((p) => p.id != 'c'),
    );
    expect(missing, contains('Hemşire: Banu, Silinmiş kişi'));
  });

  test('build: nöbetler, hafta sonu sayısı, 7A ve izin günleri', () {
    final data = PersonalRoster.build(
      plan: plan,
      person: people.first,
      people: people,
      dayShifts: const [
        DayShift(day: 9, personId: 'a', hours: 7, isSubstitute: true),
      ],
      weekendDays: const {3, 4},
    );
    expect(data.monthLabel, 'Ekim 2026');
    expect([for (final s in data.shifts) s.day], [3, 7]);
    expect(data.shifts.first.nurses, ['Ayşe', 'Banu']);
    expect(data.shifts.last.techs, ['Zeynep (24)', 'Mehmet (16B)']);
    expect(data.weekendShifts, 1);
    expect(data.dayShiftDays, [9]);
    expect(data.leaves, {
      LeaveType.annual: [12, 13, 14, 20],
    });
    expect(data.leaveDayCount, 4);
    expect(data.leaveByDay[13], LeaveType.annual);
  });
}
