import 'package:flutter_riverpod/flutter_riverpod.dart';

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

/// Kayıtlı nöbet ve mesai ayarları.
final rosterSettingsProvider = Provider(
  (ref) => ref.watch(settingsRepositoryProvider).load(),
);
