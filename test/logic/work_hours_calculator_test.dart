import 'package:flutter_test/flutter_test.dart';
import 'package:nobet_listesi/data/turkish_holidays.dart';
import 'package:nobet_listesi/logic/work_hours_calculator.dart';
import 'package:nobet_listesi/models/models.dart';

void main() {
  const calc = WorkHoursCalculator(RosterSettings());
  final holidays2026 = TurkishHolidays.forYear(2026);

  group('requiredHours', () {
    test('Ekim 2026: 20 tam gün + 28 Ekim yarım gün = 143,5 saat', () {
      final r = calc.requiredHoursBreakdown(2026, 10, holidays2026);
      expect(r.fullWorkdays, 20);
      expect(r.halfWorkdays, 1);
      expect(r.hours, 143.5);
      expect(calc.requiredHours(2026, 10, holidays2026), 143.5);
    });

    test('tatilsiz ay: Kasım 2026, 21 iş günü = 147 saat', () {
      expect(calc.requiredHours(2026, 11, holidays2026), 147);
      expect(calc.requiredHours(2026, 11, const []), 147);
    });

    test(
      'hafta sonuna denk gelen tatil saati düşürmez (30 Ağustos 2026 Pazar)',
      () {
        expect(DateTime(2026, 8, 30).weekday, DateTime.sunday);
        expect(calc.requiredHours(2026, 8, holidays2026), 21 * 7);
      },
    );

    test(
      'Mart 2026: Ramazan Bayramı, arife yarım ve hafta sonuna taşan günler',
      () {
        // 22 hafta içi gün; 20 Mart Cuma tam tatil, 19 Mart Perşembe arife;
        // 21-22 Mart hafta sonu.
        final r = calc.requiredHoursBreakdown(2026, 3, holidays2026);
        expect(r.fullWorkdays, 20);
        expect(r.halfWorkdays, 1);
        expect(r.hours, 143.5);
      },
    );

    test('Mayıs 2026: 1 ve 19 Mayıs, Kurban Bayramı ve arifesi', () {
      // 21 hafta içi gün; 1 Mayıs Cuma, 19 Mayıs Salı, 27-29 Mayıs Çar-Cum
      // tam tatil (30 Mayıs Cumartesi), 26 Mayıs Salı arife.
      final r = calc.requiredHoursBreakdown(2026, 5, holidays2026);
      expect(r.fullWorkdays, 21 - 5 - 1);
      expect(r.halfWorkdays, 1);
      expect(r.hours, 15 * 7 + 3.5);
    });

    test('başka aylardaki tatiller yok sayılır', () {
      final onlyOctober = [
        Holiday(date: DateTime(2026, 10, 29), name: 'Cumhuriyet Bayramı'),
      ];
      expect(calc.requiredHours(2026, 11, onlyOctober), 147);
      expect(calc.requiredHours(2025, 10, onlyOctober), 23 * 7);
    });

    test('ayar kapalıysa arife tam iş günü sayılır', () {
      const c = WorkHoursCalculator(
        RosterSettings(halfDayHolidayIsHalfWorkday: false),
      );
      final r = c.requiredHoursBreakdown(2026, 10, holidays2026);
      expect(r.fullWorkdays, 21);
      expect(r.halfWorkdays, 0);
      expect(r.hours, 147);
    });

    test('günlük saat ayardan gelir', () {
      const c = WorkHoursCalculator(RosterSettings(dailyRequiredHours: 8));
      expect(c.requiredHours(2026, 10, holidays2026), 20 * 8 + 4);
    });

    test('Şubat artık yıl: 2028, Ramazan Bayramı hafta sonu, arife Cuma', () {
      // 29 gün, 21 hafta içi gün; 25 Şubat Cuma arife, 26-28 Şubat
      // Cmt-Paz-Pzt -> 28 Şubat Pazartesi tam tatil.
      final r = calc.requiredHoursBreakdown(
        2028,
        2,
        TurkishHolidays.forYear(2028),
      );
      expect(r.fullWorkdays, 19);
      expect(r.halfWorkdays, 1);
    });
  });

  group('çalışılan saat ve fazla mesai', () {
    test('plandaki örnek: 7 nöbet, Ekim 2026', () {
      final required = calc.requiredHours(2026, 10, holidays2026);
      expect(calc.workedHours(7), 168);
      expect(calc.overtimeHours(7, required), 24.5);
      expect(calc.missingHours(7, required), 0);
    });

    test('eksik çalışmada fazla mesai 0, eksik saat pozitif', () {
      expect(calc.workedHours(5), 120);
      expect(calc.overtimeHours(5, 143.5), 0);
      expect(calc.missingHours(5, 143.5), 23.5);
    });

    test('nöbet süresi ayardan gelir', () {
      const c = WorkHoursCalculator(RosterSettings(shiftHours: 16));
      expect(c.workedHours(9), 144);
      expect(c.overtimeHours(9, 143.5), 0.5);
      expect(calc.workedHours(0), 0);
    });
  });
}
