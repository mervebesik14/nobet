import 'package:flutter_test/flutter_test.dart';
import 'package:nobet_listesi/logic/what_if_report.dart';
import 'package:nobet_listesi/models/models.dart';

void main() {
  const people = [
    Person(id: 'a', name: 'Ayşe', role: Role.nurse),
    Person(id: 'b', name: 'Banu', role: Role.nurse),
    Person(id: 'c', name: 'Cemile', role: Role.nurse),
  ];

  test('değişen koltuk ve yük', () {
    final r = WhatIfReport.compare(
      before: const {
        3: DayAssignment(day: 3, nurseIds: ['a', 'c']),
        4: DayAssignment(day: 4, nurseIds: ['a', 'b']),
      },
      after: const {
        3: DayAssignment(day: 3, nurseIds: ['b', 'c']),
        4: DayAssignment(day: 4, nurseIds: ['c', 'b']),
      },
      people: people,
      weekendDays: const {4},
    );
    expect(r.changedSeats, 2);
    expect(
      [for (final l in r.loads) WhatIfReport.describe(l)],
      [
        'Banu: 1 → 2 nöbet',
        'Cemile: 1 → 2 nöbet (hafta sonu 0 → 1)',
        'Ayşe: 2 → 0 nöbet (hafta sonu 1 → 0)',
      ],
    );
  });
}
