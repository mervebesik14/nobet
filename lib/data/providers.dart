import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';

import 'hive_boxes.dart';
import 'holiday_repository.dart';
import 'month_plan_repository.dart';
import 'people_repository.dart';
import 'roster_history_repository.dart';
import 'settings_repository.dart';

/// Açılmış Hive kutuları. `main.dart` içinde [HiveBoxes.open] sonucu ile
/// override edilir; testlerde geçici kutularla override edilebilir.
final hiveBoxesProvider = Provider<HiveBoxes>(
  (ref) => throw UnimplementedError(
    'hiveBoxesProvider, ProviderScope içinde override edilmeli.',
  ),
);

final peopleRepositoryProvider = Provider<PeopleRepository>(
  (ref) => PeopleRepository(ref.watch(hiveBoxesProvider).people),
);

final holidayRepositoryProvider = Provider<HolidayRepository>((ref) {
  final boxes = ref.watch(hiveBoxesProvider);
  return HolidayRepository(boxes.holidays, boxes.meta);
});

final monthPlanRepositoryProvider = Provider<MonthPlanRepository>(
  (ref) => MonthPlanRepository(ref.watch(hiveBoxesProvider).monthPlans),
);

final rosterHistoryRepositoryProvider = Provider<RosterHistoryRepository>(
  (ref) => RosterHistoryRepository(ref.watch(hiveBoxesProvider).history),
);

final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => SettingsRepository(ref.watch(hiveBoxesProvider).settings),
);

/// Kayıtlı nöbet ve mesai ayarları; Ayarlar ekranından değiştirilir.
class RosterSettingsController extends Notifier<RosterSettings> {
  @override
  RosterSettings build() => ref.watch(settingsRepositoryProvider).load();

  Future<void> update(RosterSettings settings) async {
    state = settings;
    await ref.read(settingsRepositoryProvider).save(settings);
  }

  Future<void> reset() async {
    state = const RosterSettings();
    await ref.read(settingsRepositoryProvider).reset();
  }
}

final rosterSettingsProvider =
    NotifierProvider<RosterSettingsController, RosterSettings>(
      RosterSettingsController.new,
    );

/// Tema tercihi (sistem / açık / koyu); `app_meta` kutusunda saklanır.
class ThemeModeController extends Notifier<ThemeMode> {
  static const _key = 'themeMode';

  @override
  ThemeMode build() {
    final name = ref.watch(hiveBoxesProvider).meta.get(_key) as String?;
    return ThemeMode.values.asNameMap()[name] ?? ThemeMode.system;
  }

  Future<void> set(ThemeMode mode) async {
    state = mode;
    await ref.read(hiveBoxesProvider).meta.put(_key, mode.name);
  }
}

final themeModeProvider = NotifierProvider<ThemeModeController, ThemeMode>(
  ThemeModeController.new,
);

/// Yedek durumu: son yedek ve "Sonra" denince hatırlatmanın susacağı gün.
class BackupStatus {
  const BackupStatus({this.lastBackup, this.snoozedUntil});

  final DateTime? lastBackup;
  final DateTime? snoozedUntil;
}

/// Yedek tarihlerini `app_meta` kutusunda saklar.
class BackupStatusController extends Notifier<BackupStatus> {
  static const _lastKey = 'lastBackupAt';
  static const _snoozeKey = 'backupSnoozedUntil';

  DateTime? _read(String key) {
    final v = ref.read(hiveBoxesProvider).meta.get(key);
    return v is String ? DateTime.tryParse(v) : null;
  }

  @override
  BackupStatus build() {
    ref.watch(hiveBoxesProvider);
    return BackupStatus(
      lastBackup: _read(_lastKey),
      snoozedUntil: _read(_snoozeKey),
    );
  }

  /// Yedek alındı: hatırlatma sayacı sıfırlanır.
  Future<void> markBackedUp(DateTime at) async {
    state = BackupStatus(lastBackup: at);
    final meta = ref.read(hiveBoxesProvider).meta;
    await meta.put(_lastKey, at.toIso8601String());
    await meta.delete(_snoozeKey);
  }

  /// Hatırlatmayı [until] gününe kadar sustur.
  Future<void> snooze(DateTime until) async {
    state = BackupStatus(lastBackup: state.lastBackup, snoozedUntil: until);
    await ref
        .read(hiveBoxesProvider)
        .meta
        .put(_snoozeKey, until.toIso8601String());
  }
}

final backupStatusProvider =
    NotifierProvider<BackupStatusController, BackupStatus>(
      BackupStatusController.new,
    );

/// Ay başı hatırlatmasının "Sonra" ile susturulduğu gün (`app_meta`).
class NextMonthReminderSnooze extends Notifier<DateTime?> {
  static const _key = 'nextMonthReminderSnoozedUntil';

  @override
  DateTime? build() {
    final v = ref.watch(hiveBoxesProvider).meta.get(_key);
    return v is String ? DateTime.tryParse(v) : null;
  }

  /// Hatırlatmayı [until] gününe kadar sustur.
  Future<void> snooze(DateTime until) async {
    state = until;
    await ref.read(hiveBoxesProvider).meta.put(_key, until.toIso8601String());
  }
}

final nextMonthReminderSnoozeProvider =
    NotifierProvider<NextMonthReminderSnooze, DateTime?>(
      NextMonthReminderSnooze.new,
    );
