import 'package:flutter_test/flutter_test.dart';
import 'package:nobet_listesi/logic/weekly_backup_policy.dart';

void main() {
  test('dosya adı ve tarihi', () {
    expect(
      WeeklyBackupPolicy.fileName(DateTime(2026, 11, 1, 15)),
      'nobetci-yedek-2026-11-01.json',
    );
    expect(
      WeeklyBackupPolicy.dateOf('nobetci-yedek-2026-11-01.json'),
      DateTime(2026, 11, 1),
    );
    expect(WeeklyBackupPolicy.dateOf('baska.json'), isNull);
  });

  test('ilk yedek hemen; sonra 7 gün geçince', () {
    expect(WeeklyBackupPolicy.isDue(const [], DateTime(2026, 11, 1)), isTrue);
    const files = ['nobetci-yedek-2026-11-01.json', 'not.txt'];
    expect(WeeklyBackupPolicy.isDue(files, DateTime(2026, 11, 7, 23)), isFalse);
    expect(WeeklyBackupPolicy.isDue(files, DateTime(2026, 11, 8)), isTrue);
    expect(WeeklyBackupPolicy.latest(files), DateTime(2026, 11, 1));
  });

  test('en yeni 8 dosya kalır, başka dosyalara dokunulmaz', () {
    final files = [
      for (var d = 1; d <= 10; d++)
        WeeklyBackupPolicy.fileName(DateTime(2026, 1, d * 3)),
      'benim-notum.json',
    ];
    expect(WeeklyBackupPolicy.toRemove(files), [
      'nobetci-yedek-2026-01-03.json',
      'nobetci-yedek-2026-01-06.json',
    ]);
  });
}
