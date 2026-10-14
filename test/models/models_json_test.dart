import 'package:flutter_test/flutter_test.dart';
import 'package:nobet_listesi/models/models.dart';

void main() {
  group('Role', () {
    test('Türkçe adları', () {
      expect(Role.nurse.label, 'Hemşire');
      expect(Role.radiologyTech.label, 'Radyoloji Teknikeri');
    });
  });

  test('Person JSON gidiş-dönüş', () {
    const p = Person(
      id: 'p1',
      name: 'Ayşe',
      role: Role.radiologyTech,
      isActive: false,
      colorValue: 0xFF00897B,
      isChargeNurse: true,
    );
    expect(Person.fromJson(p.toJson()), p);
    expect(
      Person.fromJson(const {
        'id': 'x',
        'name': 'X',
        'role': 'nurse',
      }).isChargeNurse,
      isFalse,
    );
  });

  test('Holiday tarihi gün başına indirir ve JSON gidiş-dönüş', () {
    final h = Holiday(
      date: DateTime(2026, 10, 28, 13, 45),
      name: 'Cumhuriyet Bayramı Arifesi',
      isHalfDay: true,
      isPredefined: true,
    );
    expect(h.date, DateTime(2026, 10, 28));
    expect(h.key, '2026-10-28');
    expect(Holiday.fromJson(h.toJson()), h);
  });

  test('DayAssignment JSON gidiş-dönüş ve personIds', () {
    const a = DayAssignment(day: 5, nurseIds: ['n1', 'n2'], techId: 't1');
    expect(a.personIds, ['n1', 'n2', 't1']);
    expect(DayAssignment.fromJson(a.toJson()), a);
    expect(const DayAssignment(day: 1).personIds, isEmpty);
  });

  test('MonthPlan JSON gidiş-dönüş (int anahtarlı atamalar dahil)', () {
    final plan = MonthPlan(
      year: 2026,
      month: 10,
      unavailableDays: const {
        'n1': [3, 14],
        't1': [20],
      },
      assignments: const {
        1: DayAssignment(day: 1, nurseIds: ['n1', 'n2'], techId: 't1'),
        2: DayAssignment(day: 2, nurseIds: ['n3', 'n4'], techId: 't2'),
      },
      generatedAt: DateTime(2026, 9, 30, 21, 15),
      isLocked: true,
      seed: 12345,
      overtimeRequests: const {'n1', 't1'},
      annualLeave: const {
        'n1': [8, 9, 10],
        't2': [15],
      },
      radiationLeave: const {
        't1': [22, 23],
      },
      requestedShifts: const {
        'n2': [4, 18],
      },
    );
    expect(MonthPlan.fromJson(plan.toJson()), plan);
    expect(plan.requestedShiftsOf('n2'), [4, 18]);
    expect(plan.references('n2'), isTrue);
    expect(plan.key, '2026-10');
    expect(plan.daysInMonth, 31);
    expect(plan.unavailableDaysOf('n1'), [3, 14]);
    expect(plan.unavailableDaysOf('yok'), isEmpty);
    expect(plan.hasRoster, isTrue);
    expect(plan.wantsOvertime('n1'), isTrue);
    expect(plan.wantsOvertime('n9'), isFalse);
    expect(plan.annualLeaveOf('n1'), [8, 9, 10]);
    expect(plan.annualLeaveOf('yok'), isEmpty);
    expect(plan.radiationLeaveOf('t1'), [22, 23]);
    expect(plan.leaveOf('t1', LeaveType.radiation), [22, 23]);
    expect(plan.leaveOf('n1', LeaveType.annual), [8, 9, 10]);
    expect(const MonthPlan(year: 2026, month: 1).hasRoster, isFalse);
  });

  test('MonthPlan.blockedDays istenmeyen gün ve tüm izinleri birleştirir', () {
    const plan = MonthPlan(
      year: 2026,
      month: 10,
      unavailableDays: {
        'n1': [3, 14],
        'n2': [5],
      },
      annualLeave: {
        'n1': [14, 20],
        't1': [2],
      },
      radiationLeave: {
        'n1': [21],
        't2': [8],
      },
    );
    // n1: kesişen 14 tekilleşir, istenmeyen + yıllık + şua sıralı birleşim.
    expect(plan.blockedDays['n1'], [3, 14, 20, 21]);
    expect(plan.blockedDays['n2'], [5]);
    expect(plan.blockedDays['t1'], [2]);
    expect(plan.blockedDays['t2'], [8]);
    // leaveDays yalnızca izinleri (istenmeyen hariç) birleştirir.
    expect(plan.leaveDaysOf('n1'), [14, 20, 21]);
    expect(plan.leaveDays['t2'], [8]);
    expect(plan.references('t2'), isTrue);
  });

  test('MonthPlan.references istenmeyen gün ve atamaları kontrol eder', () {
    const plan = MonthPlan(
      year: 2026,
      month: 2,
      unavailableDays: {
        'a': [1],
      },
      assignments: {
        1: DayAssignment(day: 1, nurseIds: ['b', 'c'], techId: 'd'),
      },
    );
    expect(plan.daysInMonth, 28);
    expect(plan.references('a'), isTrue);
    expect(plan.references('c'), isTrue);
    expect(plan.references('d'), isTrue);
    expect(plan.references('e'), isFalse);
  });

  group('RosterSettings', () {
    test('varsayılanlar plana uygun', () {
      const s = RosterSettings();
      expect(s.nursesPerDay, 2);
      expect(s.techsPerDay, 1);
      expect(s.shiftHours, 24);
      expect(s.dailyRequiredHours, 7);
      expect(s.maxEveryOtherDayChain, 2);
      expect(s.maxExtraOverAverage, isNull);
      expect(s.forbidConsecutiveDays, isTrue);
      expect(s.holidayCountsAsWeekend, isTrue);
      expect(s.halfDayHolidayIsHalfWorkday, isTrue);
      expect(s.halfDayRequiredHours, 5);
    });

    test('JSON gidiş-dönüş ve eksik alanlarda varsayılan', () {
      const s = RosterSettings(
        maxExtraOverAverage: 2,
        forbidConsecutiveDays: false,
        dailyRequiredHours: 8,
      );
      expect(RosterSettings.fromJson(s.toJson()), s);
      expect(RosterSettings.fromJson(const {}), const RosterSettings());
    });

    test('copyWith ile fazla nöbet limiti kapatılabilir', () {
      const s = RosterSettings(maxExtraOverAverage: 2);
      expect(
        s.copyWith(clearMaxExtraOverAverage: true).maxExtraOverAverage,
        isNull,
      );
      expect(s.copyWith(techsPerDay: 2).maxExtraOverAverage, 2);
    });
  });
}
