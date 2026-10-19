import 'package:flutter_test/flutter_test.dart';
import 'package:nobet_listesi/logic/shift_gaps.dart';

void main() {
  test('boşluk aradaki boş gün sayısıdır', () {
    expect(ShiftGaps.gaps([3, 8]), [(3, 8, 4)]);
    // Art arda ve gün aşırı arası 0 / 1.
    expect(ShiftGaps.gaps([1, 2, 4]), [(2, 4, 1)]);
  });

  test('izin araya girerse aralık sayılmaz', () {
    expect(ShiftGaps.gaps([3, 15], absent: {7, 8}), isEmpty);
    expect(ShiftGaps.gaps([3, 15], absent: {3, 15}), [(3, 15, 11)]);
  });

  test('önceki ayın günleri de sayılır', () {
    // Önceki ayın son günü (0) ile 6'sı arası 5 gün.
    expect(ShiftGaps.gaps([0, 6]), [(0, 6, 5)]);
  });

  test('fazla gün ve 4–5 günlük boşluk sayısı', () {
    // 1→6 (4), 6→12 (5), 12→19 (6, 1 fazla), 19→21 (1).
    final days = [1, 6, 12, 19, 21];
    expect(ShiftGaps.excess(days), 1);
    expect(ShiftGaps.longCount(days), 2);
    expect(ShiftGaps.excess(days, absent: {15}), 0);
    expect(ShiftGaps.longCount(days, absent: {3}), 1);
  });

  test('hızlı tarama listeyle aynı sonucu verir', () {
    final cases = <(List<int>, Set<int>)>[
      ([1, 6, 12, 19, 21], {}),
      ([1, 6, 12, 19, 21], {15}),
      ([-1, 6, 14], {}),
      ([2, 9, 20, 30], {10, 11}),
    ];
    for (final (days, absent) in cases) {
      expect(
        ShiftGaps.scan(
          from: -3,
          to: 31,
          works: days.contains,
          isAbsent: absent.contains,
        ),
        (
          ShiftGaps.excess(days, absent: absent),
          ShiftGaps.longCount(days, absent: absent),
          ShiftGaps.maxGapCount(days, absent: absent),
        ),
        reason: '$days $absent',
      );
    }
  });

  test('5 günlük boşluk sayısı ve eşitsizlik', () {
    // 1→7 (5 gün), 7→13 (5 gün), 13→16 (2 gün).
    expect(ShiftGaps.maxGapCount([1, 7, 13, 16]), 2);
    expect(ShiftGaps.maxGapCount([1, 7, 13, 16], absent: {3}), 1);
    expect(ShiftGaps.unevenMaxGaps([1, 0, 0]), 1);
    expect(ShiftGaps.unevenMaxGaps([1, 1, 1]), 0);
    expect(ShiftGaps.unevenMaxGaps([]), 0);
  });

  test('en uzun boşluk', () {
    expect(ShiftGaps.longest([1, 6, 12, 19, 21]), 6);
    expect(ShiftGaps.longest([1, 6, 12, 19, 21], absent: {15}), 5);
    expect(ShiftGaps.longest([4]), isNull);
  });

  test('ay sonundaki açık boşluk 5 günü aşarsa sayılır', () {
    // 30 günlük ay, son nöbet 24: 25–30 → 6 gün, ay sonunda bile aşılmış.
    expect(ShiftGaps.gaps([20, 24], monthEnd: 30), [(20, 24, 3), (24, 31, 6)]);
    expect(ShiftGaps.excess([20, 24], monthEnd: 30), 1);
    expect(ShiftGaps.longest([20, 24], monthEnd: 30), 6);
    // Ay sonu verilmezse ya da açık boşluk 5 ve altındaysa sayılmaz (sonraki
    // ayın başına bağlı).
    expect(ShiftGaps.excess([20, 24]), 0);
    expect(ShiftGaps.gaps([20, 25], monthEnd: 30), [(20, 25, 4)]);
    // Araya izin girerse sayılmaz; 4–5 günlük sayılar etkilenmez.
    expect(ShiftGaps.excess([20, 24], monthEnd: 30, absent: {28}), 0);
    expect(ShiftGaps.longCount([18, 24]), 1);
    // Hızlı tarama aynı sonucu verir.
    for (final days in [
      [20, 24],
      [3, 9, 18],
      [-2],
    ]) {
      expect(
        ShiftGaps.scan(
          from: -3,
          to: 30,
          works: days.contains,
          openEnd: true,
        ).$1,
        ShiftGaps.excess(days, monthEnd: 30),
        reason: '$days',
      );
    }
  });
}
