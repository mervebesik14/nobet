import 'package:flutter_test/flutter_test.dart';
import 'package:nobet_listesi/logic/person_totals.dart';
import 'package:nobet_listesi/logic/totals_columns.dart';

void main() {
  test('değerler, sıra ve adlardan okuma', () {
    const t = PersonTotals(shifts: 9, weekendShifts: 3, overtimeHours: 12.5);
    expect(TotalsColumn.shifts.valueOf(t), 9);
    expect(TotalsColumn.overtime.valueOf(t), 12.5);
    expect(TotalsColumn.ordered({TotalsColumn.overtime, TotalsColumn.shifts}), [
      TotalsColumn.shifts,
      TotalsColumn.overtime,
    ]);
    expect(TotalsColumn.fromNames(['weekend', 'x']), {TotalsColumn.weekend});
  });
}
