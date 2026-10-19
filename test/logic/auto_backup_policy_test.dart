import 'package:flutter_test/flutter_test.dart';
import 'package:nobet_listesi/logic/auto_backup_policy.dart';

void main() {
  final t0 = DateTime(2026, 10, 19, 9);

  group('AutoBackupPolicy.toRemove', () {
    test('ilk yedekte silinecek yok', () {
      expect(AutoBackupPolicy.toRemove(const [], t0), isEmpty);
    });

    test('10 dakika içindeki değişiklik en yeni yedeğin yerini alır', () {
      final old = t0.subtract(const Duration(hours: 1));
      final recent = t0.subtract(const Duration(minutes: 9));
      expect(AutoBackupPolicy.toRemove([recent, old], t0), [recent]);
    });

    test('10 dakikadan eskiyse yeni yedek eklenir', () {
      final last = t0.subtract(AutoBackupPolicy.mergeWindow);
      expect(AutoBackupPolicy.toRemove([last], t0), isEmpty);
    });

    test('en fazla 20 yedek: en eskiler silinir', () {
      final existing = [
        for (var i = 1; i <= AutoBackupPolicy.maxCount; i++)
          t0.subtract(Duration(hours: i)),
      ];
      expect(AutoBackupPolicy.toRemove(existing, t0), [
        t0.subtract(const Duration(hours: AutoBackupPolicy.maxCount)),
      ]);
    });

    test('birleştirmede sayı aşılmaz, eski yedek silinmez', () {
      final existing = [
        for (var i = 0; i < AutoBackupPolicy.maxCount; i++)
          t0.subtract(Duration(hours: i, minutes: 1)),
      ];
      expect(AutoBackupPolicy.toRemove(existing, t0), [
        t0.subtract(const Duration(minutes: 1)),
      ]);
    });
  });
}
