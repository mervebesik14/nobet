import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:nobet_listesi/data/hive_boxes.dart';
import 'package:nobet_listesi/data/holiday_repository.dart';
import 'package:nobet_listesi/data/month_plan_repository.dart';
import 'package:nobet_listesi/data/people_repository.dart';
import 'package:nobet_listesi/data/providers.dart';
import 'package:nobet_listesi/data/settings_repository.dart';
import 'package:nobet_listesi/models/models.dart';

void main() {
  late Directory dir;
  late HiveBoxes boxes;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('nobet_test_');
    Hive.init(dir.path);
    boxes = await HiveBoxes.open();
  });

  tearDown(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  /// Uygulamanın kapatılıp açılmasını taklit eder.
  Future<void> reopen() async {
    await Hive.close();
    Hive.init(dir.path);
    boxes = await HiveBoxes.open();
  }

  group('PeopleRepository', () {
    const ayse = Person(id: '1', name: 'Ayşe', role: Role.nurse);
    const ali = Person(id: '2', name: 'Ali', role: Role.radiologyTech);
    const banu = Person(id: '3', name: 'Banu', role: Role.nurse);

    test('kaydeder, yeniden açınca geri gelir', () async {
      await PeopleRepository(boxes.people).save(ayse);
      await PeopleRepository(boxes.people).save(ali);
      await reopen();

      final repo = PeopleRepository(boxes.people);
      expect(repo.getAll(), [ali, ayse]);
      expect(repo.getById('1'), ayse);
    });

    test('rol ve aktiflik süzgeci, pasifleştirme, silme', () async {
      final repo = PeopleRepository(boxes.people);
      for (final p in [ayse, ali, banu]) {
        await repo.save(p);
      }
      await repo.deactivate('3');

      expect(repo.getById('3')!.isActive, isFalse);
      expect(repo.getActive(), [ali, ayse]);
      expect(repo.getByRole(Role.nurse), [ayse]);
      expect(repo.getByRole(Role.nurse, activeOnly: false).length, 2);

      await repo.save(ayse.copyWith(name: 'Ayşe K.'));
      expect(repo.getById('1')!.name, 'Ayşe K.');

      await repo.delete('2');
      expect(repo.getById('2'), isNull);
    });
  });

  group('HolidayRepository', () {
    final republicEve = Holiday(
      date: DateTime(2026, 10, 28),
      name: 'Cumhuriyet Bayramı Arifesi',
      isHalfDay: true,
      isPredefined: true,
    );
    final republic = Holiday(
      date: DateTime(2026, 10, 29),
      name: 'Cumhuriyet Bayramı',
      isPredefined: true,
    );
    final newYear = Holiday(date: DateTime(2027, 1, 1), name: 'Yılbaşı');

    test('kaydeder, aya göre listeler, yeniden açınca geri gelir', () async {
      expect(HolidayRepository(boxes.holidays, boxes.meta).isEmpty, isTrue);
      await HolidayRepository(
        boxes.holidays,
        boxes.meta,
      ).saveAll([newYear, republic, republicEve]);
      await reopen();

      final repo = HolidayRepository(boxes.holidays, boxes.meta);
      expect(repo.getAll(), [republicEve, republic, newYear]);
      expect(repo.getForMonth(2026, 10), [republicEve, republic]);
      expect(repo.getForMonth(2026, 11), isEmpty);
      expect(repo.getByDate(DateTime(2026, 10, 29, 9)), republic);
    });

    test('aynı güne yazmak üzerine yazar, silme çalışır', () async {
      final repo = HolidayRepository(boxes.holidays, boxes.meta);
      await repo.save(republic);
      await repo.save(republic.copyWith(isHalfDay: true));
      expect(repo.getAll().single.isHalfDay, isTrue);

      await repo.delete(DateTime(2026, 10, 29));
      expect(repo.getAll(), isEmpty);
    });
  });

  group('MonthPlanRepository', () {
    test('kaydeder, yeniden açınca atamalarıyla geri gelir', () async {
      final plan = MonthPlan(
        year: 2026,
        month: 10,
        unavailableDays: const {
          'n1': [3, 4],
        },
        assignments: const {
          1: DayAssignment(day: 1, nurseIds: ['n1', 'n2'], techId: 't1'),
          2: DayAssignment(day: 2, nurseIds: ['n3', 'n4'], techId: 't2'),
        },
        generatedAt: DateTime(2026, 9, 30, 20),
        isLocked: true,
      );
      await MonthPlanRepository(boxes.monthPlans).save(plan);
      await reopen();

      final repo = MonthPlanRepository(boxes.monthPlans);
      expect(repo.get(2026, 10), plan);
      expect(repo.get(2026, 11), isNull);
    });

    test('getOrCreate yoksa oluşturur, varsa mevcut planı döner', () async {
      final repo = MonthPlanRepository(boxes.monthPlans);
      final created = await repo.getOrCreate(2026, 11);
      expect(created, const MonthPlan(year: 2026, month: 11));
      expect(repo.get(2026, 11), created);

      await repo.save(created.copyWith(isLocked: true));
      expect((await repo.getOrCreate(2026, 11)).isLocked, isTrue);
    });

    test('sıralama, kişi referansı ve silme', () async {
      final repo = MonthPlanRepository(boxes.monthPlans);
      await repo.save(
        const MonthPlan(
          year: 2026,
          month: 12,
          assignments: {
            1: DayAssignment(day: 1, nurseIds: ['n1', 'n2'], techId: 't1'),
          },
        ),
      );
      await repo.save(const MonthPlan(year: 2026, month: 9));

      expect(repo.getAll().map((p) => p.key), ['2026-09', '2026-12']);
      expect(repo.isPersonReferenced('t1'), isTrue);
      expect(repo.isPersonReferenced('x'), isFalse);

      await repo.delete(2026, 12);
      expect(repo.isPersonReferenced('t1'), isFalse);
    });
  });

  group('SettingsRepository', () {
    test('kayıt yoksa varsayılanlar döner', () {
      expect(SettingsRepository(boxes.settings).load(), const RosterSettings());
    });

    test(
      'kaydeder, yeniden açınca geri gelir, reset varsayılana döner',
      () async {
        const custom = RosterSettings(
          maxExtraOverAverage: 2,
          forbidConsecutiveDays: false,
          dailyRequiredHours: 7.5,
        );
        await SettingsRepository(boxes.settings).save(custom);
        await reopen();

        final repo = SettingsRepository(boxes.settings);
        expect(repo.load(), custom);

        await repo.reset();
        expect(repo.load(), const RosterSettings());
      },
    );
  });

  test("provider'lar override edilen kutuları kullanır", () async {
    final container = ProviderContainer(
      overrides: [hiveBoxesProvider.overrideWithValue(boxes)],
    );
    addTearDown(container.dispose);

    await container
        .read(peopleRepositoryProvider)
        .save(const Person(id: 'x', name: 'Zeynep', role: Role.nurse));
    expect(boxes.people.get('x')?.name, 'Zeynep');
    expect(
      container.read(settingsRepositoryProvider).load(),
      const RosterSettings(),
    );
    expect(container.read(holidayRepositoryProvider).getAll(), isEmpty);
    expect(container.read(monthPlanRepositoryProvider).getAll(), isEmpty);
  });
}
