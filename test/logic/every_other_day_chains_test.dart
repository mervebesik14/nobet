import 'package:flutter_test/flutter_test.dart';
import 'package:nobet_listesi/logic/every_other_day_chains.dart';

void main() {
  test('en uzun zincirler', () {
    expect(EveryOtherDayChains.of({3, 5, 7, 12, 14, 20}), [
      [3, 5, 7],
      [12, 14],
    ]);
    expect(EveryOtherDayChains.of({1, 3, 5, 7, 9}), [
      [1, 3, 5, 7, 9],
    ]);
    expect(EveryOtherDayChains.of({1, 4, 8}), isEmpty);
  });

  test('sayılar', () {
    const days = {1, 3, 5, 7, 10, 12, 20, 22, 24};
    expect(EveryOtherDayChains.dayCount(days), 9);
    expect(EveryOtherDayChains.countsByLength(days), {4: 1, 2: 1, 3: 1});
    expect(EveryOtherDayChains.longest(days), 4);
    expect(EveryOtherDayChains.longest({1, 9}), 0);
  });

  test('etiketler', () {
    expect(EveryOtherDayChains.lengthLabel(2), "2'li");
    expect(EveryOtherDayChains.lengthLabel(3), "3'lü");
    expect(EveryOtherDayChains.lengthLabel(4), "4'lü");
    expect(EveryOtherDayChains.lengthLabel(5), "5'li");
    expect(EveryOtherDayChains.lengthLabel(6), "6'lı");
    expect(EveryOtherDayChains.lengthLabel(9), "9'lu");
    expect(EveryOtherDayChains.lengthLabel(10), "10'lu");
    expect(EveryOtherDayChains.format([3, 5, 7]), '3-5-7');
  });
}
