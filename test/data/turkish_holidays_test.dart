import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:nobet_listesi/data/holiday_repository.dart';
import 'package:nobet_listesi/data/turkish_holidays.dart';
import 'package:nobet_listesi/models/models.dart';

import '../helpers.dart';

void main() {
  Holiday? on(List<Holiday> list, int month, int day) =>
      list.where((h) => h.date.month == month && h.date.day == day).firstOrNull;

  group('TurkishHolidays.forYear', () {
    test('sabit tarihli tatiller her yıl gelir', () {
      for (final year in [2026, 2031]) {
        final list = TurkishHolidays.forYear(year);
        for (final (m, d) in [
          (1, 1),
          (4, 23),
          (5, 1),
          (5, 19),
          (7, 15),
          (8, 30),
          (10, 29),
        ]) {
          final h = on(list, m, d);
          expect(h, isNotNull, reason: '$year-$m-$d');
          expect(h!.isHalfDay, isFalse);
          expect(h.isPredefined, isTrue);
        }
        expect(on(list, 10, 28)!.isHalfDay, isTrue);
      }
    });

    test('2026 dini bayramları plandaki tarihlerde', () {
      final list = TurkishHolidays.forYear(2026);
      expect(on(list, 3, 19)!.isHalfDay, isTrue);
      expect(on(list, 3, 19)!.name, 'Ramazan Bayramı Arifesi');
      for (final d in [20, 21, 22]) {
        expect(on(list, 3, d)!.isHalfDay, isFalse);
      }
      expect(on(list, 3, 20)!.name, 'Ramazan Bayramı 1. Gün');
      expect(on(list, 3, 23), isNull);

      expect(on(list, 5, 26)!.isHalfDay, isTrue);
      for (final d in [27, 28, 29, 30]) {
        expect(on(list, 5, d)!.isHalfDay, isFalse);
      }
      expect(on(list, 5, 30)!.name, 'Kurban Bayramı 4. Gün');
      expect(on(list, 5, 31), isNull);

      // 7 sabit + 28 Ekim arifesi + 4 Ramazan + 5 Kurban.
      expect(list.length, 17);
    });

    test('aynı güne düşen tatiller birleşir, tam gün kazanır', () {
      // 2027: Kurban Bayramı 16-19 Mayıs; 4. gün 19 Mayıs'a denk gelir.
      final list = TurkishHolidays.forYear(2027);
      final may19 = on(list, 5, 19)!;
      expect(may19.name, contains('Gençlik ve Spor Bayramı'));
      expect(may19.name, contains('Kurban Bayramı 4. Gün'));
      expect(may19.isHalfDay, isFalse);
      expect(list.where((h) => h.key == may19.key).length, 1);
      expect(on(list, 5, 15)!.isHalfDay, isTrue);
    });

    test('sıralı ve dini bayram tablosu olmayan yılda yalnızca sabitler', () {
      final list = TurkishHolidays.forYear(2026);
      final sorted = [...list]..sort((a, b) => a.date.compareTo(b.date));
      expect(list, sorted);

      expect(TurkishHolidays.hasReligiousHolidays(2026), isTrue);
      expect(TurkishHolidays.hasReligiousHolidays(2028), isTrue);
      expect(TurkishHolidays.hasReligiousHolidays(2031), isFalse);
      expect(TurkishHolidays.forYear(2031).length, 8);
    });
  });

  group('HolidayRepository.ensureYearSeeded', () {
    late HolidayRepository repo;

    setUp(() async {
      final boxes = await openTestBoxes();
      repo = HolidayRepository(boxes.holidays, boxes.meta);
    });

    tearDown(() => Hive.close());

    test('ilk çağrıda yükler, ikincide dokunmaz', () async {
      expect(await repo.ensureYearSeeded(2026), isTrue);
      expect(repo.getAll().length, 17);
      expect(repo.getAll().every((h) => h.isPredefined), isTrue);
      expect(repo.seededYears, {2026});

      // Kullanıcı bir tatili siler; yeniden yükleme onu geri getirmez.
      await repo.delete(DateTime(2026, 7, 15));
      expect(await repo.ensureYearSeeded(2026), isFalse);
      expect(repo.getByDate(DateTime(2026, 7, 15)), isNull);
    });

    test('aynı güne kullanıcının eklediği tatil korunur', () async {
      final mine = Holiday(date: DateTime(2027, 1, 1), name: 'Benim tatilim');
      await repo.save(mine);

      await repo.ensureYearSeeded(2027);
      expect(repo.getByDate(DateTime(2027, 1, 1)), mine);
      expect(
        repo.getForMonth(2027, 4).single.name,
        'Ulusal Egemenlik ve Çocuk Bayramı',
      );
      expect(repo.seededYears, {2027});
    });
  });
}
