import 'package:flutter_test/flutter_test.dart';
import 'package:nobet_listesi/logic/roster_summary.dart';
import 'package:nobet_listesi/logic/shift_pay.dart';
import 'package:nobet_listesi/models/models.dart';

void main() {
  test('kapalı: saat ücreti 0', () {
    expect(ShiftPay.enabled(const RosterSettings()), isFalse);
    expect(
      ShiftPay.enabled(const RosterSettings(shiftHourlyRate: 156.35)),
      isTrue,
    );
  });

  test('normal ve bayram saatleri, damga vergisi', () {
    const s = RosterSettings(shiftHourlyRate: 100);
    final e = ShiftPay.estimate(
      overtimeHours: 50,
      holidayShiftHours: 24,
      settings: s,
    );
    expect(e.paidHours, 50);
    expect(e.holidayHours, 24);
    expect(e.normalHours, 26);
    // 100 × (26 + 24 × 1,25) = 5600
    expect(e.gross, closeTo(5600, 1e-9));
    expect(e.stamp, closeTo(5600 * 0.00759, 1e-9));
    expect(e.net, closeTo(5600 - 5600 * 0.00759, 1e-9));
    expect(e.capped, isFalse);
  });

  test('sınır yoksa bütün fazla saat ödenir', () {
    final e = ShiftPay.estimate(
      overtimeHours: 150,
      holidayShiftHours: 0,
      settings: const RosterSettings(shiftHourlyRate: 100),
    );
    expect(e.paidHours, 150);
    expect(e.capped, isFalse);
  });

  test('riskli birim ve saat sınırı', () {
    const s = RosterSettings(
      shiftHourlyRate: 100,
      riskyUnit: true,
      payHourCap: 130,
    );
    final e = ShiftPay.estimate(
      overtimeHours: 150,
      holidayShiftHours: 0,
      settings: s,
    );
    expect(e.paidHours, 130);
    expect(e.capped, isTrue);
    expect(e.gross, closeTo(100 * 1.5 * 130, 1e-9));
    // Fazla mesai yoksa ücret yok.
    expect(
      ShiftPay.estimate(
        overtimeHours: 0,
        holidayShiftHours: 24,
        settings: s,
      ).gross,
      0,
    );
  });

  test('aylık özette kişi başı tahmini ücret', () {
    // Kasım 2026: gereken 21 × 7 = 147 saat. 8 nöbet = 192 saat → 45 fazla.
    const people = [Person(id: 'a', name: 'Ayşe', role: Role.nurse)];
    final s = RosterSummary.build(
      year: 2026,
      month: 11,
      assignments: {
        for (final d in [2, 5, 8, 11, 14, 17, 20, 23])
          d: DayAssignment(day: d, nurseIds: const ['a']),
      },
      people: people,
      holidays: const [],
      settings: const RosterSettings(shiftHourlyRate: 100),
    );
    final a = s.people.single;
    expect(a.overtimeHours, 45);
    expect(a.estimatedPay, closeTo(4500 * (1 - ShiftPay.stampRate), 1e-6));
    // Saat ücreti yoksa 0.
    final off = RosterSummary.build(
      year: 2026,
      month: 11,
      assignments: const {
        2: DayAssignment(day: 2, nurseIds: ['a']),
      },
      people: people,
      holidays: const [],
      settings: const RosterSettings(),
    );
    expect(off.people.single.estimatedPay, 0);
  });
}
