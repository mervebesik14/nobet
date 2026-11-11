import 'package:flutter_test/flutter_test.dart';
import 'package:nobet_listesi/logic/leave_impact.dart';
import 'package:nobet_listesi/models/models.dart';

void main() {
  const people = [
    Person(id: 'a', name: 'Ayşe', role: Role.nurse),
    Person(id: 'b', name: 'Banu', role: Role.nurse),
    Person(id: 'c', name: 'Cemile', role: Role.nurse),
    Person(id: 'd', name: 'Derya', role: Role.nurse),
    Person(id: 'e', name: 'Elif', role: Role.nurse),
    Person(id: 't', name: 'Ali', role: Role.radiologyTech),
  ];

  test('boş koltuk, sıkışık gün, aynı günlerde müsait olmayanlar', () {
    final r = LeaveImpact.assess(
      year: 2026,
      month: 11,
      people: people,
      personId: 'a',
      blockedBefore: const {
        'b': [11],
        'c': [11, 12],
        'd': [11],
      },
      blockedAfter: const {
        'a': [10, 11, 12],
        'b': [11],
        'c': [11, 12],
        'd': [11],
      },
      settings: const RosterSettings(),
      assignments: const {
        10: DayAssignment(day: 10, nurseIds: ['a', 'b']),
      },
    );
    expect(r.affectedDays, [10, 11, 12]);
    expect(r.shortDays, [11]); // yalnız Elif kalır
    expect(r.tightDays, [12]); // Banu, Derya, Elif
    expect(r.others, {'Cemile': 2, 'Banu': 1, 'Derya': 1});
    // Pay 30 × 2 / 5 = 12; 3 gün → 1,2; kişi başı 0,3.
    expect(r.extraShifts, closeTo(1.2, 1e-9));
    expect(r.extraPerPerson, closeTo(0.3, 1e-9));
    expect(r.rosterShifts, [10]);
    expect(r.verdict, LeaveVerdict.problem);
    expect(r.newIssues, isNotEmpty);
    expect(r.lines, contains('3 gün nöbete kapanır: 10, 11, 12 Kasım.'));
    expect(
      r.lines,
      contains('Koltuk boş kalır: 11 Kasım (yeterli hemşire yok).'),
    );
    expect(
      r.lines,
      contains('Diğerlerine yaklaşık 1,2 nöbet daha düşer (kişi başı 0,3).'),
    );
  });

  test('sorunsuz izin', () {
    final r = LeaveImpact.assess(
      year: 2026,
      month: 11,
      people: people,
      personId: 'a',
      blockedBefore: const {},
      blockedAfter: const {
        'a': [20],
      },
      settings: const RosterSettings(),
    );
    expect(r.verdict, LeaveVerdict.ok);
    expect(r.shortDays, isEmpty);
    expect(r.tightDays, isEmpty);
    expect(r.others, isEmpty);
  });
}
