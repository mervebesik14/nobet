import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../logic/weekly_backup_policy.dart';
import '../shared/providers.dart';
import 'backup_service.dart';
import 'providers.dart';

/// Haftalık yedeklerin yazıldığı klasör: uygulamanın Belgeler klasöründe
/// "Yedekler". iPhone'da Dosyalar › iPhone'umda › Nöbetçi › Yedekler'de
/// görünür (Info.plist: UIFileSharingEnabled); telefonun iCloud yedeğine
/// de girer. Testlerde geçici bir klasörle değiştirilir.
class BackupFolder {
  BackupFolder([this._override]);

  final Directory? _override;

  Future<Directory> directory() async {
    final base = _override ?? await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/Yedekler');
    if (!dir.existsSync()) await dir.create(recursive: true);
    return dir;
  }

  Future<List<String>> names() async => [
    for (final f in (await directory()).listSync())
      if (f is File) f.uri.pathSegments.last,
  ];

  Future<void> write(String name, String content) async =>
      File('${(await directory()).path}/$name').writeAsString(content);

  Future<void> delete(String name) async {
    final f = File('${(await directory()).path}/$name');
    if (f.existsSync()) await f.delete();
  }
}

final backupFolderProvider = Provider<BackupFolder>((ref) => BackupFolder());

/// Son haftalık dosya yedeğinin tarihi (ayarlar ekranı için).
final weeklyBackupDateProvider = FutureProvider<DateTime?>((ref) async {
  ref.watch(weeklyBackupVersionProvider);
  try {
    return WeeklyBackupPolicy.latest(
      await ref.watch(backupFolderProvider).names(),
    );
  } on Object {
    return null;
  }
});

/// Yedek yazılınca artar; [weeklyBackupDateProvider] yenilensin.
final weeklyBackupVersionProvider = NotifierProvider<_Version, int>(
  _Version.new,
);

class _Version extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}

/// Gerekirse (son yedekten 7 gün geçmişse) yedeği yazar; yazdıysa true.
/// Kişi ve ay planı yoksa yazılmaz.
Future<bool> writeWeeklyBackupIfDue(Ref ref) => _write(
  folder: ref.read(backupFolderProvider),
  now: ref.read(clockProvider)(),
  export: (now) => BackupService(ref.read(hiveBoxesProvider)).export(now: now),
  bump: () => ref.read(weeklyBackupVersionProvider.notifier).bump(),
  force: false,
);

/// Ayarlardan "Şimdi yaz": günü beklemeden yazar (aynı günün dosyası
/// yenilenir).
Future<bool> writeWeeklyBackupNow(WidgetRef ref) => _write(
  folder: ref.read(backupFolderProvider),
  now: ref.read(clockProvider)(),
  export: (now) => BackupService(ref.read(hiveBoxesProvider)).export(now: now),
  bump: () => ref.read(weeklyBackupVersionProvider.notifier).bump(),
  force: true,
);

Future<bool> _write({
  required BackupFolder folder,
  required DateTime now,
  required Map<String, dynamic> Function(DateTime) export,
  required void Function() bump,
  required bool force,
}) async {
  final existing = await folder.names();
  if (!force && !WeeklyBackupPolicy.isDue(existing, now)) return false;
  final data = export(now);
  if ((data['people'] as List).isEmpty &&
      (data['monthPlans'] as List).isEmpty) {
    return false;
  }
  await folder.write(
    WeeklyBackupPolicy.fileName(now),
    const JsonEncoder.withIndent(' ').convert(data),
  );
  for (final old in WeeklyBackupPolicy.toRemove([
    ...existing,
    WeeklyBackupPolicy.fileName(now),
  ])) {
    await folder.delete(old);
  }
  bump();
  return true;
}

/// Açılıştan kısa süre sonra ve uygulama açık kaldıkça günde bir kez
/// haftalık yedeği denetler. Uygulama kökünde izlenir.
final weeklyFileBackupWatcherProvider = Provider<void>((ref) {
  Future<void> check() async {
    try {
      await writeWeeklyBackupIfDue(ref);
    } on Object {
      // Sessiz: yedek yazılamazsa uygulama durmaz.
    }
  }

  final first = Timer(const Duration(seconds: 5), check);
  final daily = Timer.periodic(const Duration(hours: 24), (_) => check());
  ref.onDispose(() {
    first.cancel();
    daily.cancel();
  });
});
