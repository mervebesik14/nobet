import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:nobet_listesi/data/hive_boxes.dart';
import 'package:nobet_listesi/features/people/people_controller.dart';
import 'package:nobet_listesi/models/models.dart';

import '../../helpers.dart';

void main() {
  late HiveBoxes boxes;
  late ProviderContainer container;

  PeopleController controller() => container.read(peopleProvider.notifier);
  List<Person> people() => container.read(peopleProvider);

  setUp(() async {
    boxes = await openTestBoxes();
    container = ProviderContainer(overrides: boxOverrides(boxes));
  });

  tearDown(() async {
    container.dispose();
    await Hive.close();
  });

  test('ekler, adı temizler ve Türkçe alfabe sırasıyla listeler', () async {
    await controller().add(name: '  Zeynep   Kaya ', role: Role.nurse);
    await controller().add(name: 'Çiğdem', role: Role.radiologyTech);
    await controller().add(name: 'Cem', role: Role.nurse, isActive: false);

    expect(people().map((p) => p.name), ['Cem', 'Çiğdem', 'Zeynep Kaya']);
    expect(people().first.isActive, isFalse);
    expect(boxes.people.length, 3);
    expect(people().map((p) => p.id).toSet().length, 3);
  });

  test('günceller', () async {
    final p = await controller().add(name: 'Ayşe', role: Role.nurse);
    await controller().update(p.copyWith(name: 'Ayşe Demir', isActive: false));

    expect(people().single.name, 'Ayşe Demir');
    expect(boxes.people.get(p.id)!.isActive, isFalse);
  });

  test('isNameTaken büyük/küçük harf ve boşluk farkını gözetmez', () async {
    final p = await controller().add(name: 'Işıl Yılmaz', role: Role.nurse);

    expect(controller().isNameTaken('ışıl  yılmaz'), isTrue);
    expect(controller().isNameTaken('IŞIL YILMAZ '), isTrue);
    expect(controller().isNameTaken('Işıl'), isFalse);
    expect(controller().isNameTaken('Işıl Yılmaz', exceptId: p.id), isFalse);
  });

  group('remove', () {
    test('hiçbir planda geçmeyen kişiyi siler', () async {
      final p = await controller().add(name: 'Ali', role: Role.radiologyTech);

      expect(await controller().remove(p.id), RemovalOutcome.deleted);
      expect(people(), isEmpty);
      expect(boxes.people.get(p.id), isNull);
    });

    test('nöbet atamasında geçen kişiyi pasifleştirir', () async {
      final p = await controller().add(name: 'Ali', role: Role.radiologyTech);
      await boxes.monthPlans.put(
        '2026-10',
        MonthPlan(
          year: 2026,
          month: 10,
          assignments: {
            1: DayAssignment(day: 1, nurseIds: const ['x', 'y'], techId: p.id),
          },
        ),
      );

      expect(await controller().remove(p.id), RemovalOutcome.deactivated);
      expect(people().single.isActive, isFalse);
    });

    test('istenmeyen günlerde geçen kişi de silinmez', () async {
      final p = await controller().add(name: 'Banu', role: Role.nurse);
      await boxes.monthPlans.put(
        '2026-11',
        MonthPlan(
          year: 2026,
          month: 11,
          unavailableDays: {
            p.id: const [5],
          },
        ),
      );

      expect(controller().isReferenced(p.id), isTrue);
      expect(await controller().remove(p.id), RemovalOutcome.deactivated);
      expect(await controller().remove(p.id), RemovalOutcome.keptInactive);
      expect(boxes.people.get(p.id), isNotNull);
    });
  });
}
