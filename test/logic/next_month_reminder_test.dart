import 'package:flutter_test/flutter_test.dart';
import 'package:nobet_listesi/logic/next_month_reminder.dart';

void main() {
  group('NextMonthReminder', () {
    bool due(
      DateTime today, {
      bool hasPeople = true,
      bool hasRoster = false,
      bool viewing = false,
      DateTime? snoozedUntil,
    }) => NextMonthReminder.isDue(
      today: today,
      hasPeople: hasPeople,
      nextMonthHasRoster: hasRoster,
      viewingNextMonth: viewing,
      snoozedUntil: snoozedUntil,
    );

    test('ayın 17sinden önce hatırlatılmaz', () {
      expect(due(DateTime(2026, 10, 16)), isFalse);
      expect(due(DateTime(2026, 10, 17)), isTrue);
      expect(due(DateTime(2026, 10, 31)), isTrue);
    });

    test('gelecek ayın listesi varsa ya da kişi yoksa hatırlatılmaz', () {
      expect(due(DateTime(2026, 10, 25), hasRoster: true), isFalse);
      expect(due(DateTime(2026, 10, 25), hasPeople: false), isFalse);
    });

    test('gelecek ay zaten açıksa hatırlatılmaz', () {
      expect(due(DateTime(2026, 10, 25), viewing: true), isFalse);
    });

    test('Sonra denince susma gününe kadar susar', () {
      final until = DateTime(2026, 10, 23);
      expect(due(DateTime(2026, 10, 22), snoozedUntil: until), isFalse);
      expect(due(DateTime(2026, 10, 23), snoozedUntil: until), isTrue);
    });

    test('gelecek ay: aralıktan sonra ocak', () {
      expect(
        NextMonthReminder.nextMonth(DateTime(2026, 12, 21)),
        DateTime(2027, 1),
      );
    });
  });
}
