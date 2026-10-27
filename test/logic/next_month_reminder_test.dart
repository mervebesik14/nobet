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
      int day = 16,
    }) => NextMonthReminder.isDue(
      today: today,
      hasPeople: hasPeople,
      nextMonthHasRoster: hasRoster,
      viewingNextMonth: viewing,
      snoozedUntil: snoozedUntil,
      day: day,
    );

    test('ayın 16sından önce hatırlatılmaz', () {
      expect(due(DateTime(2026, 10, 15)), isFalse);
      expect(due(DateTime(2026, 10, 16)), isTrue);
      expect(due(DateTime(2026, 10, 31)), isTrue);
    });

    test('seçilen günden itibaren hatırlatılır (en geç 28)', () {
      expect(due(DateTime(2026, 10, 4), day: 5), isFalse);
      expect(due(DateTime(2026, 10, 5), day: 5), isTrue);
      expect(due(DateTime(2026, 10, 27), day: 31), isFalse);
      expect(due(DateTime(2026, 10, 28), day: 31), isTrue);
    });

    test('gün etiketi iyelik ekiyle', () {
      expect([1, 2, 3, 6, 9, 10, 16, 20, 28].map(NextMonthReminder.dayLabel), [
        "1'i",
        "2'si",
        "3'ü",
        "6'sı",
        "9'u",
        "10'u",
        "16'sı",
        "20'si",
        "28'i",
      ]);
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

  group('bildirimler', () {
    List<({DateTime at, DateTime month})> plan(
      DateTime now, {
      Set<String> rosters = const {},
      int count = 3,
      int day = 16,
    }) => NextMonthReminder.notifications(
      now: now,
      hasRoster: (y, m) => rosters.contains('$y-$m'),
      count: count,
      day: day,
    );

    test('her ayın 16sı 10:00, ertesi ay için', () {
      expect(plan(DateTime(2026, 10, 27)), [
        (at: DateTime(2026, 11, 16, 10), month: DateTime(2026, 12)),
        (at: DateTime(2026, 12, 16, 10), month: DateTime(2027)),
        (at: DateTime(2027, 1, 16, 10), month: DateTime(2027, 2)),
      ]);
    });

    test('bu ayın 16sı henüz gelmediyse o da girer; saat geçtiyse girmez', () {
      expect(
        plan(DateTime(2026, 10, 16, 9, 59), count: 1).single.at,
        DateTime(2026, 10, 16, 10),
      );
      expect(
        plan(DateTime(2026, 10, 16, 10), count: 1).single.at,
        DateTime(2026, 11, 16, 10),
      );
    });

    test('seçilen gün; 28\'den sonrası 28 olur', () {
      expect(
        plan(DateTime(2026, 10, 27), day: 1, count: 1).single.at,
        DateTime(2026, 11, 1, 10),
      );
      expect(
        plan(DateTime(2027, 1, 30), day: 30, count: 1).single.at,
        DateTime(2027, 2, 28, 10),
      );
    });

    test('listesi oluşturulan ayın bildirimi düşer', () {
      expect(
        plan(DateTime(2026, 10, 27), rosters: {'2026-12'}).map((n) => n.month),
        [DateTime(2027), DateTime(2027, 2), DateTime(2027, 3)],
      );
    });
  });
}
