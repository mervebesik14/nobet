import 'package:flutter_test/flutter_test.dart';
import 'package:nobet_listesi/logic/roster_generator.dart';
import 'package:nobet_listesi/logic/roster_options.dart';
import 'package:nobet_listesi/logic/roster_summary.dart';
import 'package:nobet_listesi/models/models.dart';

void main() {
  const people = [
    Person(id: 'a', name: 'Ayşe', role: Role.nurse),
    Person(id: 'b', name: 'Banu', role: Role.nurse),
    Person(id: 'c', name: 'Sorumlu', role: Role.nurse, isChargeNurse: true),
    Person(id: 't', name: 'Ali', role: Role.radiologyTech),
    Person(id: 'u', name: 'Can', role: Role.radiologyTech),
  ];

  RosterOptionStats stats(
    Map<int, DayAssignment> assignments, {
    List<RosterIssue> issues = const [],
    double score = 0,
  }) {
    final summary = RosterSummary.build(
      year: 2026,
      month: 11,
      assignments: assignments,
      people: people,
      holidays: const [],
      settings: const RosterSettings(),
    );
    return RosterOptionStats.of(
      RosterResult(
        assignments: assignments,
        score: score,
        issues: issues,
        seed: 0,
      ),
      summary,
    );
  }

  test('farklar rol içinde, sorumlu hemşire hariç; eksik koltuk toplamı', () {
    // 1 Kasım Pazar, 2 Pazartesi, 3 Salı, 7 Cumartesi.
    final s = stats(
      {
        1: const DayAssignment(day: 1, nurseIds: ['a'], techId: 't'),
        3: const DayAssignment(day: 3, nurseIds: ['a', 'c'], techId: 't'),
        7: const DayAssignment(day: 7, nurseIds: ['a'], techId: 'u'),
      },
      issues: const [
        RosterIssue(day: 1, role: Role.nurse, missing: 1, message: ''),
        RosterIssue(day: 7, role: Role.nurse, missing: 1, message: ''),
      ],
    );
    expect(s.missing, 2);
    expect(s.shiftSpread, 3); // Ayşe 3, Banu 0
    expect(s.weekendSpread, 2); // Ayşe 2, Banu 0
    expect(s.everyOtherDayPairs, 2); // Ayşe 1-3, Ali 1-3
  });

  test('en iyi: önce eksik, sonra farklar, sonra puan', () {
    final even = stats({
      1: const DayAssignment(day: 1, nurseIds: ['a'], techId: 't'),
      2: const DayAssignment(day: 2, nurseIds: ['b'], techId: 'u'),
    }, score: 5);
    final evenBetterScore = stats({
      1: const DayAssignment(day: 1, nurseIds: ['b'], techId: 'u'),
      2: const DayAssignment(day: 2, nurseIds: ['a'], techId: 't'),
    }, score: 2);
    final uneven = stats({
      1: const DayAssignment(day: 1, nurseIds: ['a'], techId: 't'),
      3: const DayAssignment(day: 3, nurseIds: ['a'], techId: 'u'),
    }, score: 0);
    expect(RosterOptionStats.best([uneven, even, evenBetterScore]), 2);
  });
}
