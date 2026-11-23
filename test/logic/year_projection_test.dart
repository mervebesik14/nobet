import 'package:flutter_test/flutter_test.dart';
import 'package:nobet_listesi/logic/person_totals.dart';
import 'package:nobet_listesi/logic/year_close.dart';
import 'package:nobet_listesi/logic/year_projection.dart';
import 'package:nobet_listesi/logic/yearly_summary.dart';
import 'package:nobet_listesi/models/models.dart';

YearlyRow row(
  String id,
  Role role,
  int shifts,
  int avail, {
  bool charge = false,
}) => YearlyRow(
  personId: id,
  name: id,
  role: role,
  totals: PersonTotals(shifts: shifts, availableDays: avail, months: 6),
  byMonth: const {},
  isChargeNurse: charge,
);

void main() {
  test('yıl sonu tahmini: fark büyür, kalan aylarda gereken', () {
    // Ocak–Haziran 2026: 181 gün; kalan 184 gün.
    final rows = YearProjection.build(
      year: 2026,
      summary: YearlySummary(
        rows: [
          row('a', Role.nurse, 30, 181),
          row('b', Role.nurse, 24, 181),
          row('s', Role.nurse, 5, 181, charge: true),
          row('t', Role.radiologyTech, 20, 181),
        ],
        months: const [1, 2, 3, 4, 5, 6],
      ),
    );
    // Sorumlu hemşire ve tek kişilik rol yok.
    expect([for (final r in rows) r.personId], ['a', 'b']);
    final a = rows.first, b = rows.last;
    expect(a.diffNow, closeTo(3, 1e-9));
    expect(b.diffNow, closeTo(-3, 1e-9));
    expect(a.diffEnd, closeTo(6.05, 0.05));
    expect(b.diffEnd, closeTo(-6.05, 0.05));
    expect(a.needed, closeTo(24.45, 0.05));
    expect(b.needed, closeTo(30.45, 0.05));
    expect(YearProjection.signed(6.06), '+6,1');
    expect(YearProjection.signed(-2), '−2');
    expect(YearProjection.signed(0.02), '0');
  });

  test('gelecek yılın bayram planı', () {
    final turns = YearClose.holidayTurns(
      year: 2026,
      thisYear: [
        Holiday(date: DateTime(2026, 5, 27), name: 'Kurban Bayramı 1. Gün'),
        Holiday(date: DateTime(2026, 5, 28), name: 'Kurban Bayramı 2. Gün'),
      ],
      nextHolidays: [
        Holiday(date: DateTime(2027, 5, 16), name: 'Kurban Bayramı 1. Gün'),
        Holiday(date: DateTime(2027, 5, 17), name: 'Kurban Bayramı 2. Gün'),
        Holiday(date: DateTime(2027, 1, 1), name: 'Yılbaşı'),
      ],
      plans: const [
        MonthPlan(
          year: 2026,
          month: 5,
          assignments: {
            27: DayAssignment(day: 27, nurseIds: ['a']),
            28: DayAssignment(day: 28, nurseIds: ['b']),
          },
        ),
      ],
      name: (id) => {'a': 'Ayşe', 'b': 'Banu'}[id]!,
    );
    expect(turns.first.kind, 'Yılbaşı');
    expect(turns.first.lastWorkers, isEmpty);
    expect(turns.last.kind, 'Kurban Bayramı');
    expect(turns.last.dates, '16–17 Mayıs');
    expect(turns.last.lastWorkers, ['Ayşe', 'Banu']);
    final text = YearClose.holidayText(2026, turns);
    expect(
      text,
      contains("Kurban Bayramı (16–17 Mayıs): 2026'de tutanlar: Ayşe, Banu"),
    );
    expect(YearClose.next({YearStep.summary}), YearStep.reports);
  });
}
