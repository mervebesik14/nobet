import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';

import 'hive_boxes.dart';
import 'holiday_repository.dart';
import 'month_plan_repository.dart';
import 'people_repository.dart';
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
