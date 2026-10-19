import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:nobet_listesi/data/auto_backup_service.dart';
import 'package:nobet_listesi/data/backup_service.dart';
import 'package:nobet_listesi/data/hive_boxes.dart';
import 'package:nobet_listesi/logic/auto_backup_policy.dart';
import 'package:nobet_listesi/models/models.dart';
import 'package:nobet_listesi/shared/providers.dart';

import '../helpers.dart';

void main() {
  late HiveBoxes boxes;
  late AutoBackupService service;
  final t0 = DateTime(2026, 10, 19, 9);

  setUp(() async {
    boxes = await openTestBoxes();
    service = AutoBackupService(boxes);
  });

  tearDown(() => Hive.close());

  Future<void> addPerson(String id) =>
      boxes.people.put(id, Person(id: id, name: id, role: Role.nurse));

  group('AutoBackupService', () {
    test('boş kurulumda yedek alınmaz', () async {
      expect(await service.snapshot(t0), isFalse);
      expect(service.entries(), isEmpty);
    });

    test('veri değişmediyse yeni yedek alınmaz', () async {
      await addPerson('a');
      expect(await service.snapshot(t0), isTrue);
      expect(await service.snapshot(t0.add(const Duration(hours: 1))), isFalse);
      expect(service.entries().map((e) => e.at), [t0]);
    });

    test('10 dakika içindeki değişiklik son yedeğin üstüne yazılır', () async {
      await addPerson('a');
      await service.snapshot(t0);
      await addPerson('b');
      final t1 = t0.add(const Duration(minutes: 5));
      expect(await service.snapshot(t1), isTrue);
      expect(service.entries().map((e) => e.at), [t1]);
      expect(service.entries().single.info.people, 2);
    });

    test('sonraki değişiklik yeni yedek: en yenisi önce', () async {
      await addPerson('a');
      await service.snapshot(t0);
      await addPerson('b');
      final t1 = t0.add(const Duration(hours: 1));
      await service.snapshot(t1);
      final entries = service.entries();
      expect(entries.map((e) => e.at), [t1, t0]);
      expect(entries.map((e) => e.info.people), [2, 1]);
    });

    test('en fazla 20 yedek tutulur', () async {
      for (var i = 0; i < AutoBackupPolicy.maxCount + 3; i++) {
        await addPerson('p$i');
        await service.snapshot(t0.add(Duration(hours: i)));
      }
      final entries = service.entries();
      expect(entries, hasLength(AutoBackupPolicy.maxCount));
      expect(entries.last.at, t0.add(const Duration(hours: 3)));
    });

    test('otomatik yedekten geri yükleme; yedekler silinmez', () async {
      await addPerson('a');
      await service.snapshot(t0);
      await boxes.people.clear();
      await addPerson('x');
      await service.snapshot(t0.add(const Duration(hours: 1)));

      await BackupService(boxes).restore(service.load(t0));
      expect(boxes.people.keys, ['a']);
      expect(service.entries(), hasLength(2));
    });
  });

  testWidgets('veri değişince birkaç saniye sonra yedek alınır', (
    tester,
  ) async {
    var now = t0;
    final container = ProviderContainer(
      overrides: [
        ...boxOverrides(boxes),
        clockProvider.overrideWithValue(() => now),
      ],
    );
    addTearDown(container.dispose);
    container.read(autoBackupWatcherProvider);
    final auto = container.read(autoBackupServiceProvider);

    // Açılışta veri yok: yedek alınmaz.
    await tester.pump(autoBackupDelay);
    expect(auto.entries(), isEmpty);

    await tester.runAsync(() => addPerson('a'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(auto.entries(), isEmpty, reason: 'değişiklik sürerken beklenir');
    await tester.pump(autoBackupDelay);
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    expect(auto.entries().map((e) => e.at), [t0]);

    now = t0.add(const Duration(hours: 1));
    await tester.runAsync(() => addPerson('b'));
    await tester.pump();
    await tester.pump(autoBackupDelay);
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    expect(auto.entries().map((e) => e.info.people), [2, 1]);
  });
}
