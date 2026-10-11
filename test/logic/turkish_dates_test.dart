import 'package:flutter_test/flutter_test.dart';
import 'package:nobet_listesi/logic/turkish_dates.dart';

void main() {
  test('formatDayMonth', () {
    expect(formatDayMonth(14, 10), '14 Ekim');
    expect(formatDayMonth(1, 1), '1 Ocak');
    expect(formatDayMonth(31, 12), '31 Aralık');
  });
}
