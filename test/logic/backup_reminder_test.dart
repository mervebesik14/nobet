import 'package:flutter_test/flutter_test.dart';
import 'package:nobet_listesi/logic/backup_reminder.dart';

void main() {
  final today = DateTime(2026, 10, 20, 15);

  test('veri yoksa hatırlatılmaz', () {
    expect(BackupReminder.isDue(today: today, hasData: false), isFalse);
  });

  test('hiç yedek yoksa hatırlatılır', () {
    expect(BackupReminder.isDue(today: today, hasData: true), isTrue);
  });

  test('14 gün dolunca hatırlatılır', () {
    bool due(DateTime last) =>
        BackupReminder.isDue(today: today, hasData: true, lastBackup: last);
    expect(due(DateTime(2026, 10, 7, 23)), isFalse); // 13 gün
    expect(due(DateTime(2026, 10, 6)), isTrue); // 14 gün
    expect(BackupReminder.daysSince(today, DateTime(2026, 10, 6, 9)), 14);
    expect(BackupReminder.daysSince(today, null), isNull);
  });

  test('"Sonra" denince susma süresi boyunca hatırlatılmaz', () {
    bool due(DateTime until) =>
        BackupReminder.isDue(today: today, hasData: true, snoozedUntil: until);
    expect(due(DateTime(2026, 10, 21)), isFalse);
    expect(due(DateTime(2026, 10, 20)), isTrue);
  });
}
