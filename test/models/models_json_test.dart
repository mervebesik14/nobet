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
    );
    expect(Person.fromJson(p.toJson()), p);
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
    );
    expect(MonthPlan.fromJson(plan.toJson()), plan);
    expect(plan.key, '2026-10');
    expect(plan.daysInMonth, 31);
    expect(plan.unavailableDaysOf('n1'), [3, 14]);
    expect(plan.unavailableDaysOf('yok'), isEmpty);
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
