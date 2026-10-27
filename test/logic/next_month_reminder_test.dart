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

    test('Başladım denince kart çıkmaz', () {
      expect(
        NextMonthReminder.isDue(
          today: DateTime(2026, 10, 20),
          hasPeople: true,
          nextMonthHasRoster: false,
          acknowledged: true,
        ),
        isFalse,
      );
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
      Set<String> acked = const {},
      int count = 3,
      int day = 16,
      int hour = 10,
      int minute = 0,
      int interval = 24,
    }) => NextMonthReminder.notifications(
      now: now,
      hasRoster: (y, m) => rosters.contains('$y-$m'),
      acknowledged: (y, m) => acked.contains('$y-$m'),
      count: count,
      day: day,
      hour: hour,
      minute: minute,
      intervalHours: interval,
    );

    List<DateTime> times(List<({DateTime at, DateTime month})> l) => [
      for (final n in l) n.at,
    ];

    test('ayın 16sı 10:00\'da başlar, her gün aynı saatte tekrarlar', () {
      expect(plan(DateTime(2026, 10, 11)), [
        (at: DateTime(2026, 10, 16, 10), month: DateTime(2026, 11)),
        (at: DateTime(2026, 10, 17, 10), month: DateTime(2026, 11)),
        (at: DateTime(2026, 10, 18, 10), month: DateTime(2026, 11)),
      ]);
    });

    test(
      '16sı geçtiyse tekrar yarından devam eder; saat geçtiyse o gün yok',
      () {
        expect(times(plan(DateTime(2026, 10, 27, 9), count: 2)), [
          DateTime(2026, 10, 27, 10),
          DateTime(2026, 10, 28, 10),
        ]);
        expect(times(plan(DateTime(2026, 10, 27, 10), count: 1)), [
          DateTime(2026, 10, 28, 10),
        ]);
      },
    );

    test('tekrar liste ayı başlayınca durur, sonra yeni ay', () {
      final l = plan(DateTime(2026, 10, 30, 12), count: 3);
      expect(l.map((n) => (n.at.month, n.at.day, n.month.month)), [
        (10, 31, 11),
        (11, 16, 12),
        (11, 17, 12),
      ]);
    });

    test('Başladım denen ya da listesi olan ayın bildirimi düşer', () {
      expect(
        plan(DateTime(2026, 10, 27), acked: {'2026-11'}, count: 1).single,
        (at: DateTime(2026, 11, 16, 10), month: DateTime(2026, 12)),
      );
      expect(
        plan(
          DateTime(2026, 10, 27),
          rosters: {'2026-11', '2026-12'},
          count: 1,
        ).single,
        (at: DateTime(2026, 12, 16, 10), month: DateTime(2027)),
      );
    });

    test('saatlik tekrar gece (22:00 sonrası) susar', () {
      expect(times(plan(DateTime(2026, 10, 16), interval: 6, count: 4)), [
        DateTime(2026, 10, 16, 10),
        DateTime(2026, 10, 16, 16),
        DateTime(2026, 10, 17, 10),
        DateTime(2026, 10, 17, 16),
      ]);
      expect(times(plan(DateTime(2026, 10, 16), interval: 3, count: 5)), [
        DateTime(2026, 10, 16, 10),
        DateTime(2026, 10, 16, 13),
        DateTime(2026, 10, 16, 16),
        DateTime(2026, 10, 16, 19),
        DateTime(2026, 10, 17, 10),
      ]);
    });

    test('birkaç günde bir tekrar', () {
      expect(times(plan(DateTime(2026, 10, 16), interval: 72)), [
        DateTime(2026, 10, 16, 10),
        DateTime(2026, 10, 19, 10),
        DateTime(2026, 10, 22, 10),
      ]);
    });

    test('seçilen gün, saat ve dakika; 28\'den sonrası 28 olur', () {
      expect(
        plan(
          DateTime(2026, 10, 27),
          day: 1,
          hour: 8,
          minute: 30,
          count: 1,
        ).single,
        (at: DateTime(2026, 10, 27, 8, 30), month: DateTime(2026, 11)),
      );
      expect(
        plan(DateTime(2027, 2, 1), day: 30, count: 1).single.at,
        DateTime(2027, 2, 28, 10),
      );
    });

    test('etiketler', () {
      expect(NextMonthReminder.timeLabel(9, 5), '09:05');
      expect(NextMonthReminder.intervals.map(NextMonthReminder.intervalLabel), [
        '3 saatte bir',
        '6 saatte bir',
        '12 saatte bir',
        'Her gün',
        '2 günde bir',
        '3 günde bir',
      ]);
    });
  });
}
