import 'package:flutter_test/flutter_test.dart';
import 'package:nobet_listesi/data/turkish_holidays.dart';
import 'package:nobet_listesi/logic/leave_balance.dart';
import 'package:nobet_listesi/models/models.dart';

void main() {
  final holidays = TurkishHolidays.forYear(2026);
  const people = [
    Person(id: 'a', name: 'Ayşe', role: Role.nurse, annualLeaveDays: 20),
    Person(id: 'b', name: 'Banu', role: Role.nurse),
  ];

  test('yalnız iş günleri sayılır, yıllar ayrı', () {
    // Ekim 2026: 26–30 (Pzt–Cuma), 29 Ekim resmi tatil → 4 iş günü;
    // 31 Cmt sayılmaz. Kasım 2–3 (Pzt–Sal) → 2.
    final plans = [
      const MonthPlan(
        year: 2026,
        month: 10,
        annualLeave: {
          'a': [26, 27, 28, 29, 30, 31],
        },
      ),
      const MonthPlan(
        year: 2026,
        month: 11,
        annualLeave: {
          'a': [2, 3],
        },
      ),
      const MonthPlan(
        year: 2025,
        month: 12,
        annualLeave: {
          'a': [1, 2, 3],
        },
      ),
    ];
    final b = LeaveBalances.forYear(
      year: 2026,
      plans: plans,
      people: people,
      holidays: holidays,
      settings: const RosterSettings(),
    );
    expect(b.keys, ['a']);
    expect(b['a'], (allowance: 20, used: 6, remaining: 14));
    expect(LeaveBalances.label(b['a']!), '6 / 20 gün kullanıldı · 14 kaldı');
    expect(
      LeaveBalances.label((allowance: 5, used: 7, remaining: -2)),
      '7 / 5 gün kullanıldı · 2 gün aşıldı',
    );
  });
}
