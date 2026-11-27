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

  test('yıl içi izinler: yıllık izin iş günü, şua ve rapor takvim günü', () {
    final plans = [
      const MonthPlan(
        year: 2026,
        month: 10,
        // 26–31 Ekim: 29 resmi tatil, 31 Cmt → 4 iş günü.
        annualLeave: {
          'a': [26, 27, 28, 29, 30, 31],
        },
        sickLeave: {
          'b': [3, 4, 5],
        },
      ),
      const MonthPlan(
        year: 2026,
        month: 3,
        radiationLeave: {
          'a': [10, 11, 9],
        },
        sickLeave: {
          'b': [1],
        },
      ),
      const MonthPlan(
        year: 2025,
        month: 12,
        sickLeave: {
          'b': [1, 2],
        },
      ),
    ];
    final l = YearLeaves.forYear(
      year: 2026,
      plans: plans,
      people: people,
      holidays: holidays,
      settings: const RosterSettings(),
    );
    expect(l['a']!.count(LeaveType.annual), 4);
    expect(l['a']!.count(LeaveType.radiation), 3);
    expect(l['a']!.count(LeaveType.sick), 0);
    expect(l['a']!.days[LeaveType.radiation], {
      3: [9, 10, 11],
    });
    expect(l['b']!.count(LeaveType.sick), 4);
    expect(l['b']!.days[LeaveType.sick]!.keys, [3, 10]);
    expect(l['b']!.isEmpty, isFalse);
    expect(
      YearLeaves.forYear(
        year: 2026,
        plans: const [],
        people: people,
        holidays: holidays,
        settings: const RosterSettings(),
      )['a']!.isEmpty,
      isTrue,
    );
    expect(YearLeaves.unitOf(LeaveType.annual), 'iş günü');
    expect(YearLeaves.unitOf(LeaveType.sick), 'gün');
  });

  test(
    'yıl içi izinler: yıllık izin boşluklarıyla (nöbet, 7A çalışılan gün)',
    () {
      // Ekim 2026: Ayşe 9 (Cuma) ve 19 (Pzt) nöbette; 12–16 izin.
      final plans = [
        MonthPlan(
          year: 2026,
          month: 10,
          assignments: {
            for (var d = 1; d <= 31; d++)
              d: DayAssignment(
                day: d,
                nurseIds: [if (d == 9 || d == 19) 'a' else 'b'],
              ),
          },
          annualLeave: const {
            'a': [12, 13, 14, 15, 16],
          },
          // 8 Ekim rapor: boşluk orada durur (9 zaten nöbet).
          sickLeave: const {
            'a': [8],
          },
        ),
      ];
      final l = YearLeaves.forYear(
        year: 2026,
        plans: plans,
        people: people,
        holidays: holidays,
        settings: const RosterSettings(),
      )['a']!;
      expect(l.stretches, hasLength(1));
      expect(l.stretches.single.start, DateTime(2026, 10, 10));
      expect(l.stretches.single.end, DateTime(2026, 10, 18));
      expect(l.awayDays, 9);
      expect(l.count(LeaveType.annual), 5);

      // Listesi olmayan ayda boşluk hesaplanmaz: yalnız izin günleri.
      final noRoster = YearLeaves.forYear(
        year: 2026,
        plans: const [
          MonthPlan(
            year: 2026,
            month: 11,
            annualLeave: {
              'a': [2, 3],
            },
          ),
        ],
        people: people,
        holidays: holidays,
        settings: const RosterSettings(),
      )['a']!;
      expect(noRoster.awayDays, 2);
    },
  );
}
