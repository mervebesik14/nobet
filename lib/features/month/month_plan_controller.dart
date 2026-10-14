import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../../logic/feasibility_checker.dart';
import '../../logic/leave_rules.dart';
import '../../logic/roster_generator.dart';
import '../../logic/roster_validator.dart';
import '../../logic/yearly_summary.dart';
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

/// Bu oturumda kullanıcının kilidini açtığı geçmiş aylar (`yyyy-MM`).
/// Uygulama yeniden açılınca geçmiş aylar yine kilitlenir.
class UnlockedPastMonths extends Notifier<Set<String>> {
  @override
  Set<String> build() => {};

  void add(String key) => state = {...state, key};
}

final unlockedPastMonthsProvider =
    NotifierProvider<UnlockedPastMonths, Set<String>>(UnlockedPastMonths.new);

/// Seçili ayın planı. Kayıtlı plan yoksa boş bir plan oluşturulup kaydedilir.
/// Geçmiş aylardaki listeler salt okunurdur: açılınca kilitlenir, kullanıcı
/// kilidi açabilir.
class MonthPlanController extends Notifier<MonthPlan> {
  @override
  MonthPlan build() {
    final month = ref.watch(planMonthProvider);
    final repo = ref.read(monthPlanRepositoryProvider);
    final existing = repo.get(month.year, month.month);
    if (existing == null) {
      final plan = MonthPlan(year: month.year, month: month.month);
      repo.save(plan);
      return plan;
    }
    if (existing.hasRoster &&
        !existing.isLocked &&
        isPastMonth(existing) &&
        !ref.read(unlockedPastMonthsProvider).contains(existing.key)) {
      final locked = existing.copyWith(isLocked: true);
      repo.save(locked);
      return locked;
    }
    return existing;
  }

  /// [plan] bugünün ayından önce mi?
  bool isPastMonth(MonthPlan plan) {
    final today = ref.read(todayProvider);
    return plan.year < today.year ||
        (plan.year == today.year && plan.month < today.month);
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

  /// Kişinin [day] gününü verilen türde izin yapar ya da bundan çıkarır.
  /// Kilitli ayda değişiklik yapılmaz ve false döner.
  Future<bool> toggleLeave(String personId, LeaveType type, int day) {
    final days = {...state.leaveOf(personId, type)};
    if (!days.remove(day)) days.add(day);
    return _setLeaveDays(personId, type, days);
  }

  /// [start]–[end] (dahil) gün aralığını verilen türde izne ekler. Aralık
  /// ayın günlerine kırpılır; ters verilirse sıraya sokulur.
  Future<bool> addLeaveRange(
    String personId,
    LeaveType type,
    int start,
    int end,
  ) {
    final lo = start <= end ? start : end;
    final hi = start <= end ? end : start;
    final days = {...state.leaveOf(personId, type)};
    for (var d = lo; d <= hi; d++) {
      if (d >= 1 && d <= state.daysInMonth) days.add(d);
    }
    return _setLeaveDays(personId, type, days);
  }

  /// [start]–[end] (dahil) gün aralığını verilen türdeki izinlerden çıkarır.
  Future<bool> removeLeaveRange(
    String personId,
    LeaveType type,
    int start,
    int end,
  ) {
    final lo = start <= end ? start : end;
    final hi = start <= end ? end : start;
    final days = {...state.leaveOf(personId, type)};
    for (var d = lo; d <= hi; d++) {
      days.remove(d);
    }
    return _setLeaveDays(personId, type, days);
  }

  /// Kişinin bu aydaki verilen türdeki tüm izin günlerini kaldırır.
  Future<bool> clearLeave(String personId, LeaveType type) =>
      _setLeaveDays(personId, type, {});

  /// Kişinin bu ay fazla mesai isteyip istemediğini değiştirir.
  /// Kilitli ayda değişmez ve false döner.
  Future<bool> setOvertime(String personId, bool wants) async {
    if (state.isLocked) return false;
    final set = {...state.overtimeRequests};
    if (wants) {
      set.add(personId);
    } else {
      set.remove(personId);
    }
    state = state.copyWith(overtimeRequests: set);
    await ref.read(monthPlanRepositoryProvider).save(state);
    return true;
  }

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

  Future<bool> _setLeaveDays(
    String personId,
    LeaveType type,
    Set<int> days,
  ) async {
    if (state.isLocked) return false;
    final map = {
      ...switch (type) {
        LeaveType.annual => state.annualLeave,
        LeaveType.radiation => state.radiationLeave,
      },
    };
    if (days.isEmpty) {
      map.remove(personId);
    } else {
      map[personId] = days.toList()..sort();
    }
    state = switch (type) {
      LeaveType.annual => state.copyWith(annualLeave: map),
      LeaveType.radiation => state.copyWith(radiationLeave: map),
    };
    await ref.read(monthPlanRepositoryProvider).save(state);
    return true;
  }

  /// Oluşturulmuş nöbet listesini sıfırlar (atamalar, tohum, oluşturma anı
  /// silinir). İstenmeyen günler, yıllık izinler ve fazla mesai istekleri
  /// korunur. Kilitli ayda sıfırlanmaz ve false döner.
  Future<bool> resetRoster() async {
    if (state.isLocked) return false;
    state = MonthPlan(
      year: state.year,
      month: state.month,
      unavailableDays: state.unavailableDays,
      annualLeave: state.annualLeave,
      radiationLeave: state.radiationLeave,
      overtimeRequests: state.overtimeRequests,
      nurseOnly: state.nurseOnly,
    );
    await ref.read(monthPlanRepositoryProvider).save(state);
    return true;
  }

  /// Nöbet listesini oluşturur ve plana kaydeder. [seed] verilmezse yeni
  /// rastgele tohum kullanılır (her "Yeniden oluştur" farklı liste verir).
  /// Kilit burada kontrol edilmez; onayı ekran ister.
  Future<RosterResult> generate({int? seed, bool? nurseOnly}) async {
    final plan = state;
    final onlyNurses = nurseOnly ?? plan.nurseOnly;
    final base = ref.read(rosterSettingsProvider);
    final generator = RosterGenerator(
      year: plan.year,
      month: plan.month,
      people: ref.read(peopleProvider),
      unavailableDays: computeEffectiveBlockedDays(
        plan,
        ref.read(holidaysProvider),
      ),
      holidays: ref.read(holidaysProvider),
      settings: effectiveSettings(base, nurseOnly: onlyNurses),
      seed: seed ?? Random().nextInt(1 << 31),
      previousMonthTail: previousMonthTail(),
      overtimeRequests: plan.overtimeRequests,
      yearToDate: YearlySummary.build(
        year: plan.year,
        plans: ref.read(monthPlanRepositoryProvider).getAll(),
        people: ref.read(peopleProvider),
        holidays: ref.read(holidaysProvider),
        settings: base,
        beforeMonth: plan.month,
      ).byId,
    );
    final result = await ref.read(rosterRunnerProvider)(generator);
    state = state.copyWith(
      assignments: result.assignments,
      generatedAt: DateTime.now(),
      seed: result.seed,
      nurseOnly: onlyNurses,
    );
    await ref.read(monthPlanRepositoryProvider).save(state);
    return result;
  }

  /// Elle düzenlenmiş atamaları kaydeder. Kilitli ayda değişiklik
  /// yapılmaz ve false döner.
  Future<bool> setAssignments(Map<int, DayAssignment> assignments) async {
    if (state.isLocked) return false;
    state = state.copyWith(assignments: assignments);
    await ref.read(monthPlanRepositoryProvider).save(state);
    return true;
  }

  Future<void> setLocked(bool locked) async {
    if (!locked) ref.read(unlockedPastMonthsProvider.notifier).add(state.key);
    state = state.copyWith(isLocked: locked);
    await ref.read(monthPlanRepositoryProvider).save(state);
  }

  /// Önceki ayın son 4 gününün nöbetçileri (ay sınırında art arda gün ve
  /// gün aşırı zincir kuralları için).
  List<Set<String>> previousMonthTail() {
    final plan = state;
    final prev = DateTime(plan.year, plan.month - 1);
    final previous = ref
        .read(monthPlanRepositoryProvider)
        .get(prev.year, prev.month);
    if (previous == null || !previous.hasRoster) return const [];
    final last = previous.daysInMonth;
    return [
      for (var d = last - 3; d <= last; d++)
        {...?previous.assignments[d]?.personIds},
    ];
  }
}

/// Seçili ayın listesindeki kural ihlalleri; her değişiklikte yenilenir.
/// Bir ay yalnız hemşire ise tekniker koltuğu kapatılmış ayarlar.
RosterSettings effectiveSettings(
  RosterSettings base, {
  required bool nurseOnly,
}) => nurseOnly ? base.copyWith(techsPerDay: 0) : base;

/// Seçili ayın, (yalnız hemşire ise) teknikeri kapatılmış etkin ayarları.
final effectiveSettingsProvider = Provider<RosterSettings>((ref) {
  final nurseOnly = ref.watch(monthPlanProvider.select((p) => p.nurseOnly));
  return effectiveSettings(
    ref.watch(rosterSettingsProvider),
    nurseOnly: nurseOnly,
  );
});

final rosterViolationsProvider = Provider<List<RuleViolation>>((ref) {
  final plan = ref.watch(monthPlanProvider);
  if (!plan.hasRoster) return const [];
  return RosterValidator(ref.watch(effectiveSettingsProvider)).validate(
    year: plan.year,
    month: plan.month,
    assignments: plan.assignments,
    people: ref.watch(peopleProvider),
    unavailableDays: ref.watch(effectiveBlockedDaysProvider),
    previousMonthTail: ref.read(monthPlanProvider.notifier).previousMonthTail(),
    overtimeRequests: plan.overtimeRequests,
  );
});

RosterResult _runGenerator(RosterGenerator generator) => generator.generate();

/// Algoritmayı arayüzü dondurmadan ayrı bir isolate'te çalıştırır.
/// Testlerde doğrudan çalıştıran bir sürümle override edilir.
final rosterRunnerProvider =
    Provider<Future<RosterResult> Function(RosterGenerator)>(
      (ref) =>
          (generator) => compute(_runGenerator, generator),
    );

final monthPlanProvider = NotifierProvider<MonthPlanController, MonthPlan>(
  MonthPlanController.new,
);

/// Nöbet dağıtımında kişi başı gerçekten engellenen günler: istenmeyen
/// günler + tüm izinler + yıllık izin öncesi son iş günü ve sonrası ilk iş
/// gününe kadar kalan günler (bkz. [LeaveRules]).
Map<String, List<int>> computeEffectiveBlockedDays(
  MonthPlan plan,
  Iterable<Holiday> holidays,
) {
  final base = plan.blockedDays;
  final ids = {...base.keys, ...plan.annualLeave.keys};
  final result = <String, List<int>>{};
  for (final id in ids) {
    final days = {...?base[id]};
    days.addAll(
      LeaveRules.annualLeaveBlockedDays(
        year: plan.year,
        month: plan.month,
        annualLeaveDays: plan.annualLeaveOf(id),
        holidays: holidays,
      ),
    );
    if (days.isNotEmpty) result[id] = days.toList()..sort();
  }
  return result;
}

/// Seçili ayın etkin bloklu günleri. Üretim, uygunluk ve doğrulama kullanır.
final effectiveBlockedDaysProvider = Provider<Map<String, List<int>>>((ref) {
  final plan = ref.watch(monthPlanProvider);
  final holidays = ref.watch(holidaysProvider);
  return computeEffectiveBlockedDays(plan, holidays);
});

/// Seçili ay için liste oluşturmadan önceki uygunluk kontrolü.
final monthFeasibilityProvider = Provider<FeasibilityReport>((ref) {
  final plan = ref.watch(monthPlanProvider);
  return FeasibilityChecker(ref.watch(rosterSettingsProvider)).check(
    year: plan.year,
    month: plan.month,
    people: ref.watch(peopleProvider),
    unavailableDays: ref.watch(effectiveBlockedDaysProvider),
  );
});
