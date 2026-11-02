import 'package:flutter_test/flutter_test.dart';
import 'package:nobet_listesi/data/turkish_holidays.dart';
import 'package:nobet_listesi/logic/holiday_history.dart';
import 'package:nobet_listesi/models/models.dart';

void main() {
  test('tatil türü: gün ve arife eki düşer, ikili ad ikiye ayrılır', () {
    expect(HolidayHistory.kindsOf('Kurban Bayramı 2. Gün'), {'Kurban Bayramı'});
    expect(HolidayHistory.kindsOf('Cumhuriyet Bayramı Arifesi'), {
      'Cumhuriyet Bayramı',
    });
    expect(
      HolidayHistory.kindsOf(
        "Atatürk'ü Anma, Gençlik ve Spor Bayramı / Kurban Bayramı 3. Gün",
      ),
      {"Atatürk'ü Anma, Gençlik ve Spor Bayramı", 'Kurban Bayramı'},
    );
  });

  test('aynı bayramın geçen yılki günlerinde nöbet tutanlar', () {
    final holidays = [
      ...TurkishHolidays.forYear(2026),
      ...TurkishHolidays.forYear(2027),
    ];
    // 2026 Kurban: 27–30 Mayıs; 2027 Kurban: 16–19 Mayıs.
    final plans = [
      const MonthPlan(
        year: 2026,
        month: 5,
        assignments: {
          27: DayAssignment(day: 27, nurseIds: ['a', 'b'], techId: 't'),
          28: DayAssignment(day: 28, nurseIds: ['c', 'a']),
          10: DayAssignment(day: 10, nurseIds: ['z']),
        },
      ),
    ];
    final h = HolidayHistory.previousWorkers(
      year: 2027,
      month: 5,
      holidays: holidays,
      plans: plans,
    );
    // 2027 Kurban günlerinin hepsinde geçen Kurban'da tutanlar.
    expect(h[16], {'a', 'b', 't', 'c'});
    expect(h[19], {'a', 'b', 't', 'c'});
    // 1 Mayıs: geçen 1 Mayıs'ın listesi yok.
    expect(h.containsKey(1), isFalse);
    // Bayram olmayan gün yok.
    expect(h.containsKey(10), isFalse);
  });
}
