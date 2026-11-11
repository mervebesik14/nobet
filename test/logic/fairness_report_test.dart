import 'package:flutter_test/flutter_test.dart';
import 'package:nobet_listesi/logic/fairness_report.dart';
import 'package:nobet_listesi/logic/person_totals.dart';
import 'package:nobet_listesi/logic/request_fulfillment.dart';
import 'package:nobet_listesi/logic/roster_summary.dart';
import 'package:nobet_listesi/models/models.dart';

void main() {
  const people = [
    Person(id: 'a', name: 'Ayşe', role: Role.nurse),
    Person(id: 'b', name: 'Banu', role: Role.nurse),
    Person(id: 'c', name: 'Cemile', role: Role.nurse),
    Person(id: 't', name: 'Ali', role: Role.radiologyTech),
  ];

  test('satırlar, farklar, istekler ve kurallar', () {
    // Kasım 2026: 6 ve 7 hafta sonu, 6 Cuma; 13 Cuma.
    final summary = RosterSummary.build(
      year: 2026,
      month: 11,
      assignments: const {
        6: DayAssignment(day: 6, nurseIds: ['a'], techId: 't'),
        7: DayAssignment(day: 7, nurseIds: ['a']),
        13: DayAssignment(day: 13, nurseIds: ['a']),
        10: DayAssignment(day: 10, nurseIds: ['b']),
      },
      people: people,
      holidays: const [],
      settings: const RosterSettings(),
    );
    final report = FairnessReport.build(
      summary: summary,
      ytd: const {'a': PersonTotals(shifts: 30, weekendShifts: 8)},
      requests: const {
        'b': [
          (month: 11, kind: RequestKind.unavailable, met: true, detail: ''),
          (month: 11, kind: RequestKind.preferred, met: false, detail: ''),
        ],
      },
      settings: const RosterSettings(),
    );
    final a = report.rows.firstWhere((r) => r.personId == 'a');
    expect(a.shifts, 3);
    expect(a.weekend, 1);
    expect(a.preWeekend, 2); // 6 ve 13 Kasım Cuma
    expect(a.ytdShifts, 30);
    final b = report.rows.firstWhere((r) => r.personId == 'b');
    expect(b.ytdShifts, 1); // yıl içi yoksa bu ay
    expect((b.requestsMet, b.requestsTotal), (1, 2));
    expect(report.requestPercent, 50);

    final nurse = report.checks[Role.nurse]!;
    expect(nurse.first, (label: 'Toplam nöbet', spread: 3));
    expect(report.balancedFor(Role.nurse), isFalse);
    expect(report.checks.containsKey(Role.radiologyTech), isFalse);
    expect(
      FairnessReport.checkLine(nurse.take(2).toList()),
      'Toplam nöbet farkı 3 · Hafta sonu farkı 1',
    );
    expect(report.rules, contains('Kimse art arda iki gün nöbet tutmaz.'));
    expect(
      FairnessReport.rulesOf(
        const RosterSettings(forbidConsecutiveDays: false),
      ),
      isNot(contains('Kimse art arda iki gün nöbet tutmaz.')),
    );
  });
}
