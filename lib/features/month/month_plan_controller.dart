import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../../logic/feasibility_checker.dart';
import '../../models/models.dart';
import '../../shared/providers.dart';
import '../holidays/holidays_controller.dart';
import '../people/people_controller.dart';

/// Ay Planı ekranında seçili ay (ayın 1'i).
class PlanMonthController extends Notifier<DateTime> {
  @override
  DateTime build() {
    final today = ref.watch(todayProvider);
    return DateTime(today.year, today.month);
  }

  /// Ayı değiştirir; yeni yılın hazır tatilleri henüz yüklenmediyse yükler
  /// (takvimde tatiller renkli görünsün diye).
  Future<void> select(DateTime month) async {
    state = DateTime(month.year, month.month);
    await ref.read(holidaysProvider.notifier).ensureYearSeeded(month.year);
  }
}

final planMonthProvider = NotifierProvider<PlanMonthController, DateTime>(
  PlanMonthController.new,
);

/// Seçili ayın planı. Kayıtlı plan yoksa boş bir plan oluşturulup kaydedilir.
class MonthPlanController extends Notifier<MonthPlan> {
  @override
  MonthPlan build() {
    final month = ref.watch(planMonthProvider);
    final repo = ref.read(monthPlanRepositoryProvider);
    final existing = repo.get(month.year, month.month);
    if (existing != null) return existing;
    final plan = MonthPlan(year: month.year, month: month.month);
    repo.save(plan);
    return plan;
  }

  /// Kişinin [day] gününü istenmeyen gün yapar ya da bundan çıkarır.
  /// Kilitli ayda değişiklik yapılmaz ve false döner.
  Future<bool> toggleUnavailable(String personId, int day) {
    final days = {...state.unavailableDaysOf(personId)};
    if (!days.remove(day)) days.add(day);
    return _setDays(personId, days);
  }

  /// Kişinin bu aydaki tüm istenmeyen günlerini kaldırır.
  Future<bool> clearUnavailable(String personId) => _setDays(personId, {});

  Future<bool> _setDays(String personId, Set<int> days) async {
    if (state.isLocked) return false;
    final unavailable = {...state.unavailableDays};
    if (days.isEmpty) {
      // Boş kayıt bırakılmaz: kişi yalnızca gerçekten istenmeyen günü varsa
      // bu planda "geçiyor" sayılır.
      unavailable.remove(personId);
    } else {
      unavailable[personId] = days.toList()..sort();
    }
    state = state.copyWith(unavailableDays: unavailable);
    await ref.read(monthPlanRepositoryProvider).save(state);
    return true;
  }
}

final monthPlanProvider = NotifierProvider<MonthPlanController, MonthPlan>(
  MonthPlanController.new,
);

/// Seçili ay için liste oluşturmadan önceki uygunluk kontrolü.
final monthFeasibilityProvider = Provider<FeasibilityReport>((ref) {
  final plan = ref.watch(monthPlanProvider);
  return FeasibilityChecker(ref.watch(rosterSettingsProvider)).check(
    year: plan.year,
    month: plan.month,
    people: ref.watch(peopleProvider),
    unavailableDays: plan.unavailableDays,
  );
});
