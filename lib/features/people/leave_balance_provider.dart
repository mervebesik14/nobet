import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../../logic/leave_balance.dart';
import '../holidays/holidays_controller.dart';
import '../month/month_plan_controller.dart';
import 'people_controller.dart';

/// Yıl → izin hakkı girilmiş kişilerin yıllık izin bakiyeleri. Listeler,
/// kişiler ya da tatiller değişince yenilenir.
final leaveBalancesProvider = Provider.family<Map<String, LeaveBalance>, int>((
  ref,
  year,
) {
  ref.watch(monthPlanProvider);
  return LeaveBalances.forYear(
    year: year,
    plans: ref.watch(monthPlanRepositoryProvider).getAll(),
    people: ref.watch(peopleProvider),
    holidays: ref.watch(holidaysProvider),
    settings: ref.watch(rosterSettingsProvider),
  );
});
