import 'package:flutter_test/flutter_test.dart';
import 'package:nobet_listesi/logic/fatigue_score.dart';
import 'package:nobet_listesi/logic/person_totals.dart';

void main() {
  test('hafta sonları: Kasım 2026 (1 Pazar)', () {
    final b = FatigueScore.weekendBlocks(2026, 11);
    expect(b.first, [1]);
    expect(b[1], [7, 8]);
    expect(b.last, [28, 29]);
    expect(b, hasLength(5));
  });

  test('art arda hafta sonu ve art arda gün', () {
    final b = FatigueScore.weekendBlocks(2026, 11);
    // 1 (Paz), 8 (Paz), 21 (Cmt): 1-8 art arda; 21 tek.
    expect(FatigueScore.consecutiveWeekends({1, 8, 21}, b), 1);
    expect(FatigueScore.consecutiveWeekends({1, 7, 14, 22, 28}, b), 4);
    expect(FatigueScore.consecutivePairs({3, 4, 5, 9}), 2);
  });

  test('puan ve döküm', () {
    const t = PersonTotals(
      shifts: 8,
      everyOtherDayPairs: 2,
      consecutivePairs: 1,
      weekendShifts: 3,
      consecutiveWeekends: 2,
      nationalHolidayShifts: 1,
    );
    // 8 + 2 + 2 + 1,5 + 2 + 0,5
    expect(t.fatigue, 16);
    expect(FatigueScore.parts(t).map((p) => p.points), [8, 2, 2, 1.5, 2, 0.5]);
  });
}
