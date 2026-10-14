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

  group('silme ve pasifleştirme', () {
    test('hiçbir planda geçmeyen kişiyi siler', () async {
      final p = await controller().add(name: 'Ali', role: Role.radiologyTech);

      await controller().delete(p.id);
      expect(people(), isEmpty);
      expect(boxes.people.get(p.id), isNull);
    });

    test('nöbet atamasında geçen kişi de silinir; nöbet kaydı kalır', () async {
      final p = await controller().add(name: 'Ali', role: Role.radiologyTech);
      final plan = MonthPlan(
        year: 2026,
        month: 10,
        assignments: {
          1: DayAssignment(day: 1, nurseIds: const ['x', 'y'], techId: p.id),
        },
      );
      await boxes.monthPlans.put('2026-10', plan);
      expect(controller().isReferenced(p.id), isTrue);

      await controller().delete(p.id);
      expect(people(), isEmpty);
      expect(boxes.people.get(p.id), isNull);
      // Geçmiş liste bozulmaz; listede "Silinmiş kişi" olarak görünür.
      expect(boxes.monthPlans.get('2026-10'), plan);
    });

    test('pasif yapılan kişi kalır, aktif değildir', () async {
      final p = await controller().add(name: 'Banu', role: Role.nurse);

      await controller().deactivate(p.id);
      expect(people().single.isActive, isFalse);
      expect(boxes.people.get(p.id), isNotNull);
    });
  });

  group('tarihli pasif yapma', () {
    /// d günü hemşireler (2d, 2d+1) mod 7: kurala uygun dönüşüm.
    Map<int, DayAssignment> rotation() => {
      for (var d = 1; d <= 31; d++)
        d: DayAssignment(
          day: d,
          nurseIds: ['n${(2 * d) % 7}', 'n${(2 * d + 1) % 7}'],
          techId: 't${d % 4}',
        ),
    };

    Future<void> seedTeam() async {
      for (var i = 0; i < 8; i++) {
        await boxes.people.put(
          'n$i',
          Person(id: 'n$i', name: 'Hemşire $i', role: Role.nurse),
        );
      }
      for (var i = 0; i < 4; i++) {
        await boxes.people.put(
          't$i',
          Person(id: 't$i', name: 'Tekniker $i', role: Role.radiologyTech),
        );
      }
      container.invalidate(peopleProvider);
    }

    test('o günden sonraki nöbetler başkalarına verilir', () async {
      await seedTeam();
      final original = rotation();
      await boxes.monthPlans.put(
        '2026-10',
        MonthPlan(year: 2026, month: 10, assignments: original),
      );

      final report = await controller().deactivate(
        'n0',
        from: DateTime(2026, 10, 20),
      );

      final person = boxes.people.get('n0')!;
      expect(person.isActive, isFalse);
      expect(person.inactiveFrom, DateTime(2026, 10, 20));

      final plan = boxes.monthPlans.get('2026-10')!;
      for (var d = 1; d < 20; d++) {
        expect(plan.assignments[d], original[d], reason: 'gün $d');
      }
      final removed = [
        for (var d = 20; d <= 31; d++)
          if (original[d]!.includes('n0')) d,
      ];
      expect(report.removed, removed.length);
      expect(report.refilled + report.unfilled.length, removed.length);
      for (var d = 20; d <= 31; d++) {
        expect(plan.assignments[d]!.includes('n0'), isFalse, reason: 'gün $d');
      }
    });

    test('bitiş tarihli dönemde yalnızca dönem içi nöbetler değişir', () async {
      await seedTeam();
      final original = rotation();
      await boxes.monthPlans.put(
        '2026-10',
        MonthPlan(year: 2026, month: 10, assignments: original),
      );

      await controller().deactivate(
        'n0',
        from: DateTime(2026, 10, 10),
        until: DateTime(2026, 10, 20),
      );

      final person = boxes.people.get('n0')!;
      // Bitişi belli dönem: ertesi gün kendiliğinden yeniden aktif.
      expect(person.isActive, isTrue);
      expect(person.inactiveUntil, DateTime(2026, 10, 20));
      expect(person.isActiveOn(DateTime(2026, 10, 21)), isTrue);

      final plan = boxes.monthPlans.get('2026-10')!;
      for (var d = 1; d <= 31; d++) {
        if (d >= 10 && d <= 20) {
          expect(
            plan.assignments[d]!.includes('n0'),
            isFalse,
            reason: 'gün $d',
          );
        } else {
          // Dönem dışındaki nöbetler aynen kalır.
          expect(
            plan.assignments[d]!.includes('n0'),
            original[d]!.includes('n0'),
            reason: 'gün $d',
          );
        }
      }
    });

    test('pasiflik gününden önce biten aylara dokunulmaz', () async {
      await seedTeam();
      final september = MonthPlan(
        year: 2026,
        month: 9,
        assignments: {for (var d = 1; d <= 30; d++) d: rotation()[d]!},
      );
      await boxes.monthPlans.put('2026-09', september);

      final report = await controller().deactivate(
        'n0',
        from: DateTime(2026, 10, 1),
      );
      expect(report.removed, 0);
      expect(boxes.monthPlans.get('2026-09'), september);
    });

    test('yeniden aktif yapılınca pasif başlangıcı silinir', () async {
      await seedTeam();
      await controller().deactivate('n1', from: DateTime(2026, 10, 20));
      await controller().activate('n1');
      final p = boxes.people.get('n1')!;
      expect(p.isActive, isTrue);
      expect(p.inactiveFrom, isNull);
    });
  });
}
