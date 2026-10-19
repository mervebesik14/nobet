import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive_ce.dart';

import '../logic/auto_backup_policy.dart';
import '../shared/providers.dart';
import 'backup_service.dart';
import 'hive_boxes.dart';
import 'providers.dart';

/// Bir otomatik yedek: alındığı an ve içeriğinin özeti.
class AutoBackupEntry {
  const AutoBackupEntry({required this.at, required this.info});

  final DateTime at;
  final BackupInfo info;
}

/// Veri değiştikçe telefona sessizce yedek alır ([AutoBackupPolicy] ile en
/// son yedekler tutulur). Yanlışlıkla silinen ya da bozulan veriyi geri
/// getirir; telefon değişince işe yaramaz, onun için yedek paylaşılmalı.
class AutoBackupService {
  AutoBackupService(this._boxes);

  final HiveBoxes _boxes;

  Box<dynamic> get _box => _boxes.autoBackups;

  static String _key(DateTime at) => at.toIso8601String();

  List<DateTime> get _times =>
      [for (final k in _box.keys) ?DateTime.tryParse(k as String)]..sort();

  /// Yedeğin, alındığı an dışındaki içeriği.
  static String _signature(Map<String, dynamic> backup) =>
      jsonEncode({...backup}..remove('exportedAt'));

  /// Veri son yedekten farklıysa [now] anında yedek alır; alındıysa true.
  /// Kişi ve ay planı yoksa (boş kurulum) yedek alınmaz.
  Future<bool> snapshot(DateTime now) async {
    final data = BackupService(_boxes).export(now: now);
    if ((data['people'] as List).isEmpty &&
        (data['monthPlans'] as List).isEmpty) {
      return false;
    }
    final times = _times;
    if (times.isNotEmpty) {
      final latest = _box.get(_key(times.last));
      if (latest is String &&
          _signature(jsonDecode(latest) as Map<String, dynamic>) ==
              _signature(data)) {
        return false;
      }
    }
    for (final t in AutoBackupPolicy.toRemove(times, now)) {
      await _box.delete(_key(t));
    }
    await _box.put(_key(now), jsonEncode(data));
    return true;
  }

  /// Otomatik yedekler, en yenisi önce.
  List<AutoBackupEntry> entries() => [
    for (final t in _times.reversed)
      if (_tryLoad(t) case final backup?)
        AutoBackupEntry(at: t, info: BackupService.info(backup)),
  ];

  Map<String, dynamic>? _tryLoad(DateTime at) {
    try {
      return load(at);
    } on Object {
      return null;
    }
  }

  /// [at] anındaki yedek (doğrulanmış).
  Map<String, dynamic> load(DateTime at) {
    final text = _box.get(_key(at));
    if (text is! String) {
      throw const BackupFormatException('Yedek bulunamadı.');
    }
    return BackupService.parse(text);
  }
}

final autoBackupServiceProvider = Provider<AutoBackupService>(
  (ref) => AutoBackupService(ref.watch(hiveBoxesProvider)),
);

/// Son değişiklikten bu kadar sonra yedek alınır (art arda değişiklikler
/// tek yedek olsun).
const autoBackupDelay = Duration(seconds: 3);

/// Veri kutularını izler; değişiklik durunca otomatik yedek alır. Uygulama
/// açılınca da (veri son yedekten farklıysa) bir yedek alınır. Uygulama
/// kökünde izlenir.
final autoBackupWatcherProvider = Provider<void>((ref) {
  final boxes = ref.watch(hiveBoxesProvider);
  final service = ref.watch(autoBackupServiceProvider);
  Timer? timer;
  void schedule() {
    timer?.cancel();
    timer = Timer(autoBackupDelay, () async {
      try {
        await service.snapshot(ref.read(clockProvider)());
      } on Object {
        // Otomatik yedek sessizdir; başarısızlık uygulamayı durdurmaz.
      }
    });
  }

  final subscriptions = [
    for (final box in <Box<dynamic>>[
      boxes.people,
      boxes.holidays,
      boxes.monthPlans,
      boxes.settings,
    ])
      box.watch().listen((_) => schedule()),
  ];
  schedule();
  ref.onDispose(() {
    timer?.cancel();
    for (final s in subscriptions) {
      s.cancel();
    }
  });
});
