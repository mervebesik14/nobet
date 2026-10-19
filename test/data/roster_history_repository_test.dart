import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:nobet_listesi/data/roster_history_repository.dart';
import 'package:nobet_listesi/models/models.dart';

import '../helpers.dart';

void main() {
  late RosterHistoryRepository repo;

  setUp(() async {
    repo = RosterHistoryRepository((await openTestBoxes()).history);
  });

  tearDown(() => Hive.close());

  RosterEdit edit(String title) => RosterEdit(
    at: DateTime(2026, 10, 14, 9, 30),
    title: title,
    lines: const ['3 Ekim: Ayşe yerine Hale'],
    before: const {
      3: DayAssignment(day: 3, nurseIds: ['a', 'b'], techId: 'm'),
    },
    beforeOverrides: const {9: 'a'},
    beforeGeneratedAt: DateTime(2026, 10, 1, 8),
    beforeSeed: 42,
  );

  test('kaydeder, JSON gidiş-dönüşte veri korunur', () async {
    await repo.add(2026, 10, edit('Elle değişiklik'));
    final loaded = repo.load(2026, 10).single;
    expect(loaded.title, 'Elle değişiklik');
    expect(loaded.at, DateTime(2026, 10, 14, 9, 30));
    expect(loaded.lines, ['3 Ekim: Ayşe yerine Hale']);
    expect(loaded.before[3]!.nurseIds, ['a', 'b']);
    expect(loaded.before[3]!.techId, 'm');
    expect(loaded.beforeOverrides, {9: 'a'});
    expect(loaded.beforeGeneratedAt, DateTime(2026, 10, 1, 8));
    expect(loaded.beforeSeed, 42);
    expect(repo.load(2026, 11), isEmpty);
  });

  test('kesme ve en fazla kayıt sınırı', () async {
    for (var i = 0; i < RosterHistoryRepository.maxEntries + 5; i++) {
      await repo.add(2026, 10, edit('$i'));
    }
    final all = repo.load(2026, 10);
    expect(all.length, RosterHistoryRepository.maxEntries);
    expect(all.first.title, '5'); // en eskiler silindi

    await repo.truncate(2026, 10, 3);
    expect([for (final e in repo.load(2026, 10)) e.title], ['5', '6', '7']);
    await repo.clear(2026, 10);
    expect(repo.load(2026, 10), isEmpty);
  });
}
