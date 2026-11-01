import 'package:flutter_test/flutter_test.dart';
import 'package:nobet_listesi/logic/shift_reminder.dart';
import 'package:nobet_listesi/models/models.dart';

void main() {
  final plans = [
    const MonthPlan(
      year: 2026,
      month: 10,
      assignments: {
        5: DayAssignment(day: 5, nurseIds: ['m', 'e'], techId: 't'),
        31: DayAssignment(day: 31, nurseIds: ['m', 'n'], techId: 't'),
      },
    ),
    const MonthPlan(
      year: 2026,
      month: 11,
      assignments: {
        1: DayAssignment(day: 1, nurseIds: ['m'], techId: 't', tech16bId: 'u'),
        3: DayAssignment(day: 3, nurseIds: ['e'], techId: 'u'),
      },
    ),
  ];

  test('her nöbetten önceki akşam 20:00; geçmişler atlanır, sıralı', () {
    final items = ShiftReminder.upcoming(
      now: DateTime(2026, 10, 10),
      plans: plans,
      personId: 'm',
    );
    expect(items.map((i) => i.at), [
      DateTime(2026, 10, 30, 20),
      DateTime(2026, 10, 31, 20),
    ]);
    expect(items.first.shiftDay, DateTime(2026, 10, 31));
  });

  test('16B ayrı yazılır; saat ve sayı sınırı', () {
    final items = ShiftReminder.upcoming(
      now: DateTime(2026, 10, 1),
      plans: plans,
      personId: 'u',
      hour: 21,
      minute: 30,
    );
    expect(items.map((i) => (i.at, i.shift)), [
      (DateTime(2026, 10, 31, 21, 30), '16B'),
      (DateTime(2026, 11, 2, 21, 30), '24'),
    ]);
    expect(
      ShiftReminder.upcoming(
        now: DateTime(2026, 10, 1),
        plans: plans,
        personId: 'm',
        count: 1,
      ),
      hasLength(1),
    );
  });

  test('metin: tarih, nöbet türü ve birlikte çalışanlar', () {
    final item = ShiftReminder.upcoming(
      now: DateTime(2026, 10, 1),
      plans: plans,
      personId: 'm',
    ).first;
    const names = {'m': 'Merve', 'e': 'Emre', 't': 'Anıl'};
    expect(
      ShiftReminder.body(item, (id) => names[id]!),
      'Yarın (5 Ekim Pazartesi) nöbetin var (24).\n'
      'Hemşire: Merve, Emre · Radyoloji: Anıl',
    );
  });
}
