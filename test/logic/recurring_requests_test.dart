import 'package:flutter_test/flutter_test.dart';
import 'package:nobet_listesi/logic/month_open.dart';
import 'package:nobet_listesi/logic/recurring_requests.dart';

void main() {
  test('her Çarşamba, ayın 1. günü, bitiş tarihi', () {
    const wed = RecurringRequest(id: '1', personId: 'a', weekdays: {3});
    // Aralık 2026: Çarşambalar 2, 9, 16, 23, 30.
    expect(wed.daysIn(2026, 12), {2, 9, 16, 23, 30});
    expect(wed.describe(), 'her Çarşamba');

    final weekend = RecurringRequest(
      id: '2',
      personId: 'b',
      weekdays: const {6, 7},
      monthDays: const {1},
      until: DateTime(2026, 12, 13),
    );
    expect(weekend.daysIn(2026, 12), {1, 5, 6, 12, 13});
    expect(weekend.daysIn(2027, 1), isEmpty);
    expect(
      weekend.describe(),
      'hafta sonları, ayın 1. günü · 13 Aralık 2026 sonuna kadar',
    );
    expect(RecurringRequest.fromJson(weekend.toJson()).daysIn(2026, 12), {
      1,
      5,
      6,
      12,
      13,
    });
    expect(RecurringRequest.forMonth([wed, weekend], 2026, 12), {
      'a': {2, 9, 16, 23, 30},
      'b': {1, 5, 6, 12, 13},
    });
    expect(RecurringRequest.preview([wed], 2026, 12, (id) => 'Ayşe'), [
      'Ayşe: 2, 9, 16, 23, 30 (her Çarşamba)',
    ]);
  });

  test('ay başı adımları', () {
    expect(MonthOpen.next({}), OpenStep.recurring);
    expect(MonthOpen.next({OpenStep.recurring}), OpenStep.collect);
    expect(MonthOpen.fromNames(['collect', 'x']), {OpenStep.collect});
    expect(MonthOpen.key(2026, 1), 'monthOpen/2026-01');
    expect(MonthOpen.reminder('Aralık 2026'), contains('Aralık 2026'));
  });
}
