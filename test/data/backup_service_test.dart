import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:nobet_listesi/data/backup_service.dart';
import 'package:nobet_listesi/data/hive_boxes.dart';
import 'package:nobet_listesi/data/holiday_repository.dart';
import 'package:nobet_listesi/models/models.dart';

import '../helpers.dart';

void main() {
  late HiveBoxes boxes;

  setUp(() async {
    boxes = await openTestBoxes();
  });

  tearDown(() => Hive.close());

  Future<void> seed() async {
    await boxes.people.putAll({
      'a': const Person(id: 'a', name: 'Ayşe Işık', role: Role.nurse),
      't': const Person(
        id: 't',
        name: 'Ali',
        role: Role.radiologyTech,
        isActive: false,
        colorValue: 0xFF112233,
      ),
    });
    await HolidayRepository(boxes.holidays, boxes.meta).ensureYearSeeded(2026);
    await boxes.holidays.put(
      '2026-10-30',
      Holiday(date: DateTime(2026, 10, 30), name: 'Köprü izni'),
    );
    final plan = MonthPlan(
      year: 2026,
      month: 10,
      unavailableDays: const {
        'a': [3, 4],
      },
      assignments: const {
        1: DayAssignment(day: 1, nurseIds: ['a'], techId: 't'),
        2: DayAssignment(day: 2),
      },
      generatedAt: DateTime(2026, 9, 30, 21),
      isLocked: true,
      seed: 99,
    );
    await boxes.monthPlans.put(plan.key, plan);
    await boxes.settings.put(
      'roster',
      const RosterSettings(
        maxExtraOverAverage: 2,
        forbidConsecutiveDays: false,
        halfDayRequiredHours: 4.5,
      ),
    );
    await boxes.meta.put('themeMode', 'dark');
  }

  Map<String, Object?> snapshot() => {
    'people': {for (final k in boxes.people.keys) k: boxes.people.get(k)},
    'holidays': {for (final k in boxes.holidays.keys) k: boxes.holidays.get(k)},
    'plans': {
      for (final k in boxes.monthPlans.keys) k: boxes.monthPlans.get(k),
    },
    'settings': boxes.settings.get('roster'),
    'years': boxes.meta.get('seededHolidayYears'),
    'theme': boxes.meta.get('themeMode'),
  };

  test(
    'gidiş-dönüş: dışa aktar → temizle → geri yükle aynı veriyi verir',
    () async {
      await seed();
      final before = snapshot();
      final text = BackupService(boxes).exportJson(now: DateTime(2026, 10, 11));

      // Veri değişsin / silinsin.
      await boxes.people.clear();
      await boxes.monthPlans.put(
        '2027-01',
        const MonthPlan(year: 2027, month: 1),
      );
      await boxes.settings.clear();
      await boxes.meta.put('themeMode', 'light');

      final backup = BackupService.parse(text);
      final info = BackupService.info(backup);
      expect(info.people, 2);
      expect(info.monthPlans, 1);
      expect(info.holidays, 18);
      expect(info.exportedAt, DateTime(2026, 10, 11));

      await BackupService(boxes).restore(backup);
      expect(snapshot(), before);
      expect(boxes.monthPlans.get('2027-01'), isNull);
    },
  );

  test('diskte gidiş-dönüş: başka bir kuruluma geri yükle, kapat-aç', () async {
    await seed();
    final before = snapshot();
    final text = BackupService(boxes).exportJson();
    await Hive.close();

    // "Yeni telefon": boş bir klasörde diske yazan kutular.
    final dir = await Directory.systemTemp.createTemp('nobet_yedek_');
    addTearDown(() => dir.delete(recursive: true));
    Hive.init(dir.path);
    boxes = await HiveBoxes.open();
    expect(boxes.people.isEmpty, isTrue);
    await BackupService(boxes).restore(BackupService.parse(text));
    await Hive.close();

    Hive.init(dir.path);
    boxes = await HiveBoxes.open();
    expect(snapshot(), before);
    await Hive.close(); // klasör silinmeden önce
  });

  test('geçersiz dosyalar reddedilir, veri silinmez', () async {
    await seed();
    final before = snapshot();
    expect(
      () => BackupService.parse('bu json değil'),
      throwsA(isA<BackupFormatException>()),
    );
    expect(
      () => BackupService.parse('{"format": "baska"}'),
      throwsA(
        isA<BackupFormatException>().having(
          (e) => e.message,
          'message',
          'Bu dosya bir Nöbet Listesi yedeği değil.',
        ),
      ),
    );
    expect(
      () => BackupService.parse(
        '{"format": "nobet_listesi_yedek", "version": 99}',
      ),
      throwsA(isA<BackupFormatException>()),
    );
    await expectLater(
      BackupService(boxes).restore({
        'format': BackupService.format,
        'version': 1,
        'people': [
          {'id': 'x'},
        ],
      }),
      throwsA(isA<BackupFormatException>()),
    );
    expect(snapshot(), before);
  });
}
