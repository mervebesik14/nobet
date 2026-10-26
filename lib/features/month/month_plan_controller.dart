import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/month_plan_repository.dart';
import '../../data/providers.dart';
import '../../data/turkish_holidays.dart';
import '../../logic/block_reason.dart';
import '../../logic/day_shift_planner.dart';
import '../../logic/feasibility_checker.dart';
import '../../logic/leave_rules.dart';
import '../../logic/roster_diff.dart';
import '../../logic/roster_generator.dart';
import '../../logic/roster_import.dart';
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
    // Bir gün hem istenmeyen hem seçilmiş nöbet günü olamaz.
    final requested = {...state.requestedShiftsOf(personId)}..removeAll(days);
    return _setDays(personId, days, requested: requested);
  }

  /// Kişinin [day] gününü nöbet tutacağı gün yapar ya da bundan çıkarır.
  /// İstenmeyen günlerdeyse oradan çıkar. Kilitli ayda false döner.
  Future<bool> toggleRequestedShift(String personId, int day) {
    final requested = {...state.requestedShiftsOf(personId)};
    if (!requested.remove(day)) requested.add(day);
    final days = {...state.unavailableDaysOf(personId)}..removeAll(requested);
    return _setDays(personId, days, requested: requested);
  }

  /// Kişinin bu aydaki seçilmiş nöbet günlerini kaldırır.
  Future<bool> clearRequestedShifts(String personId) => _setDays(personId, {
    ...state.unavailableDaysOf(personId),
  }, requested: const {});

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

  /// [start]–[end] (dahil) tarih aralığını verilen türde izne ekler; aralık
  /// ay sınırını aşabilir (ör. 26 Ekim–6 Kasım). Her ayın günleri o ayın
  /// planına yazılır (plan yoksa oluşturulur). Kilitli aylar atlanır ve
  /// (ayın 1'i olarak) döner; hepsi yazıldıysa boş liste.
  Future<List<DateTime>> addLeaveDates(
    String personId,
    LeaveType type,
    DateTime start,
    DateTime end,
  ) async {
    var lo = DateTime(start.year, start.month, start.day);
    var hi = DateTime(end.year, end.month, end.day);
    if (hi.isBefore(lo)) (lo, hi) = (hi, lo);
    final repo = ref.read(monthPlanRepositoryProvider);
    final skipped = <DateTime>[];
    for (
      var m = DateTime(lo.year, lo.month);
      !m.isAfter(DateTime(hi.year, hi.month));
      m = DateTime(m.year, m.month + 1)
    ) {
      final last = DateTime(m.year, m.month + 1, 0).day;
      final from = m.year == lo.year && m.month == lo.month ? lo.day : 1;
      final to = m.year == hi.year && m.month == hi.month ? hi.day : last;
      if (m.year == state.year && m.month == state.month) {
        if (!await addLeaveRange(personId, type, from, to)) skipped.add(m);
        continue;
      }
      final plan = await repo.getOrCreate(m.year, m.month);
      if (plan.isLocked) {
        skipped.add(m);
        continue;
      }
      await repo.save(
        plan.withLeave(personId, type, {
          ...plan.leaveOf(personId, type),
          for (var d = from; d <= to; d++) d,
        }),
      );
    }
    return skipped;
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

  /// İstenmeyen günleri (ve verilirse seçilmiş nöbet günlerini) yazar.
  Future<bool> _setDays(
    String personId,
    Set<int> days, {
    Set<int>? requested,
  }) async {
    if (state.isLocked) return false;
    // Boş kayıt bırakılmaz: kişi yalnızca gerçekten günü varsa bu planda
    // "geçiyor" sayılır.
    Map<String, List<int>> put(Map<String, List<int>> map, Set<int> value) {
      final copy = {...map};
      if (value.isEmpty) {
        copy.remove(personId);
      } else {
        copy[personId] = value.toList()..sort();
      }
      return copy;
    }

    state = state.copyWith(
      unavailableDays: put(state.unavailableDays, days),
      requestedShifts: requested == null
          ? null
          : put(state.requestedShifts, requested),
    );
    await ref.read(monthPlanRepositoryProvider).save(state);
    return true;
  }

  Future<bool> _setLeaveDays(
    String personId,
    LeaveType type,
    Set<int> days,
  ) async {
    if (state.isLocked) return false;
    state = state.withLeave(personId, type, days);
    await ref.read(monthPlanRepositoryProvider).save(state);
    return true;
  }

  /// Oluşturulmuş nöbet listesini sıfırlar (atamalar, tohum, oluşturma anı
  /// silinir); izinler korunur. [clearRequests] true ise kişi istekleri
  /// (istenmeyen günler, istenen nöbet günleri, fazla mesai) de silinir.
  /// Kilitli ayda sıfırlanmaz ve false döner. Geçmişten geri alınabilir.
  Future<bool> resetRoster({bool clearRequests = false}) async {
    if (state.isLocked) return false;
    final before = state;
    state = MonthPlan(
      year: state.year,
      month: state.month,
      unavailableDays: clearRequests ? const {} : state.unavailableDays,
      annualLeave: state.annualLeave,
      radiationLeave: state.radiationLeave,
      sickLeave: state.sickLeave,
      requestedShifts: clearRequests ? const {} : state.requestedShifts,
      overtimeRequests: clearRequests ? const {} : state.overtimeRequests,
      nurseOnly: state.nurseOnly,
    );
    await ref.read(monthPlanRepositoryProvider).save(state);
    if (before.hasRoster) {
      await _record('Liste sıfırlandı', before, details: false);
    }
    return true;
  }

  /// Nöbet listesini oluşturur ve plana kaydeder. [seed] verilmezse yeni
  /// rastgele tohum kullanılır (her "Yeniden oluştur" farklı liste verir).
  /// Kilit burada kontrol edilmez; onayı ekran ister.
  Future<RosterResult> generate({int? seed, bool? nurseOnly}) async {
    final plan = state;
    final onlyNurses = nurseOnly ?? plan.nurseOnly;
    final generator = _generator(plan, onlyNurses: onlyNurses, seed: seed);
    final result = await ref.read(rosterRunnerProvider)(generator);
    final before = state;
    state = state.copyWith(
      assignments: result.assignments,
      // Yeni listede eski 7A seçimleri ve nöbet devirleri geçersiz olur.
      dayShiftOverrides: const {},
      handovers: const {},
      generatedAt: DateTime.now(),
      seed: result.seed,
      nurseOnly: onlyNurses,
    );
    await ref.read(monthPlanRepositoryProvider).save(state);
    await _record(
      before.hasRoster ? 'Liste yeniden oluşturuldu' : 'Liste oluşturuldu',
      before,
      details: false,
    );
    return result;
  }

  /// Elle girmek için boş liste açar: ayın her günü boş koltuklarla. Önceki
  /// liste varsa geçmişten geri alınabilir. Kilitli ayda false.
  Future<bool> startEmptyRoster({required bool nurseOnly}) => _replaceRoster(
    {for (var d = 1; d <= state.daysInMonth; d++) d: DayAssignment(day: d)},
    nurseOnly: nurseOnly,
    title: 'Elle giriş için boş liste açıldı',
  );

  /// Dışarıda hazırlanmış (Excel'den okunan) listeyi olduğu gibi kaydeder;
  /// kural ihlalleri her zamanki gibi uyarı olarak görünür. Dosyadaki
  /// izinler mevcut izinlere eklenir. Kilitli ayda false.
  Future<bool> importRoster(
    RosterImportResult imported, {
    required bool nurseOnly,
  }) async {
    if (state.isLocked) return false;
    var plan = state;
    for (final MapEntry(key: type, value: byPerson)
        in imported.leaves.entries) {
      for (final MapEntry(key: id, value: days) in byPerson.entries) {
        plan = plan.withLeave(id, type, {...plan.leaveOf(id, type), ...days});
      }
    }
    state = plan;
    return _replaceRoster(
      imported.assignments,
      nurseOnly: nurseOnly,
      title: "Liste Excel'den alındı",
    );
  }

  Future<bool> _replaceRoster(
    Map<int, DayAssignment> assignments, {
    required bool nurseOnly,
    required String title,
  }) async {
    if (state.isLocked) return false;
    final before = state;
    state = state.copyWith(
      assignments: assignments,
      // Yeni listede eski 7A seçimleri ve nöbet devirleri geçersiz olur.
      dayShiftOverrides: const {},
      handovers: const {},
      generatedAt: DateTime.now(),
      nurseOnly: nurseOnly,
    );
    await ref.read(monthPlanRepositoryProvider).save(state);
    await _record(title, before, details: false);
    return true;
  }

  /// Kayıtlı listeyi baştan kurmadan güncel kurallara göre düzeltir: kural
  /// bozan nöbetler en az değişiklikle kaydırılır, elle yapılanlar ve 7A
  /// seçimleri korunur. Değişen atama sayısını döndürür (kilitliyse null).
  Future<({RosterResult result, int changed})?> fixRoster() async {
    if (state.isLocked || !state.hasRoster) return null;
    final plan = state;
    final generator = _generator(
      plan,
      onlyNurses: plan.nurseOnly,
      existing: plan.assignments,
    );
    final result = await ref.read(rosterRunnerProvider)(generator);
    var changed = 0;
    for (final MapEntry(key: d, value: a) in result.assignments.entries) {
      final was = plan.assignments[d]?.personIds ?? const <String>[];
      changed += a.personIds.where((id) => !was.contains(id)).length;
    }
    if (changed > 0) {
      await setAssignments(
        result.assignments,
        title: 'Kurallara göre düzeltildi',
      );
    }
    return (result: result, changed: changed);
  }

  RosterGenerator _generator(
    MonthPlan plan, {
    required bool onlyNurses,
    int? seed,
    Map<int, DayAssignment>? existing,
  }) {
    final base = ref.read(rosterSettingsProvider);
    return RosterGenerator(
      year: plan.year,
      month: plan.month,
      people: ref.read(peopleProvider),
      unavailableDays: computeEffectiveBlockedDays(
        plan,
        ref.read(holidaysProvider),
        repository: ref.read(monthPlanRepositoryProvider),
        people: ref.read(peopleProvider),
      ),
      holidays: ref.read(holidaysProvider),
      settings: effectiveSettings(base, nurseOnly: onlyNurses),
      seed: seed ?? ref.read(rosterSeedProvider)(),
      previousMonthTail: previousMonthTail(),
      overtimeRequests: plan.overtimeRequests,
      requestedShifts: computeRequiredShifts(
        plan,
        ref.read(holidaysProvider),
        repository: ref.read(monthPlanRepositoryProvider),
      ),
      absentDays: plan.leaveDays,
      yearToDate: YearlySummary.build(
        year: plan.year,
        plans: ref.read(monthPlanRepositoryProvider).getAll(),
        people: ref.read(peopleProvider),
        holidays: ref.read(holidaysProvider),
        settings: base,
        beforeMonth: plan.month,
      ).byId,
      existing: existing,
    );
  }

  /// Değişikliği geçmişe yazar: [before] geri alma için saklanır. [details]
  /// ise satır satır fark eklenir; fark yoksa kayıt yapılmaz.
  Future<void> _record(
    String title,
    MonthPlan before, {
    bool details = true,
  }) async {
    final names = {for (final p in ref.read(peopleProvider)) p.id: p.name};
    final lines = details
        ? RosterDiff.describe(
            month: state.month,
            before: before.assignments,
            after: state.assignments,
            overridesBefore: before.dayShiftOverrides,
            overridesAfter: state.dayShiftOverrides,
            name: (id) => names[id] ?? 'Silinmiş kişi',
          )
        : const <String>[];
    if (details && lines.isEmpty) return;
    await ref
        .read(rosterHistoryRepositoryProvider)
        .add(
          state.year,
          state.month,
          RosterEdit(
            at: DateTime.now(),
            title: title,
            lines: lines,
            before: before.assignments,
            beforeOverrides: before.dayShiftOverrides,
            beforeGeneratedAt: before.generatedAt,
            beforeSeed: before.seed,
          ),
        );
    ref.read(rosterHistoryVersionProvider.notifier).bump();
  }

  /// Geçmişteki [index]. kaydı ve sonrasındakileri geri alır: liste o
  /// değişiklikten önceki hâline döner. Kilitli ayda false.
  Future<bool> undoTo(int index) async {
    if (state.isLocked) return false;
    final history = ref.read(rosterHistoryRepositoryProvider);
    final edits = history.load(state.year, state.month);
    if (index < 0 || index >= edits.length) return false;
    final edit = edits[index];
    state = state.copyWith(
      assignments: edit.before,
      dayShiftOverrides: edit.beforeOverrides,
      generatedAt: edit.beforeGeneratedAt,
      seed: edit.beforeSeed,
      clearGenerated: edit.before.isEmpty,
    );
    await ref.read(monthPlanRepositoryProvider).save(state);
    await history.truncate(state.year, state.month, index);
    ref.read(rosterHistoryVersionProvider.notifier).bump();
    return true;
  }

  /// En son değişikliği geri alır.
  Future<bool> undoLast() async {
    final count = ref
        .read(rosterHistoryRepositoryProvider)
        .load(state.year, state.month)
        .length;
    return count > 0 && await undoTo(count - 1);
  }

  /// [day] gününün 7A'sını elle [personId]'ye verir; null ise otomatik
  /// seçime döner. Kilitli ayda değişmez ve false döner.
  Future<bool> setDayShiftOverride(int day, String? personId) async {
    if (state.isLocked) return false;
    final overrides = {...state.dayShiftOverrides};
    if (personId == null) {
      overrides.remove(day);
    } else {
      overrides[day] = personId;
    }
    final before = state;
    state = state.copyWith(dayShiftOverrides: overrides);
    await ref.read(monthPlanRepositoryProvider).save(state);
    await _record('7A değişikliği', before);
    return true;
  }

  /// Elle düzenlenmiş atamaları kaydeder. Kilitli ayda değişiklik
  /// yapılmaz ve false döner.
  Future<bool> setAssignments(
    Map<int, DayAssignment> assignments, {
    String title = 'Elle değişiklik',
  }) async {
    if (state.isLocked) return false;
    final before = state;
    state = state.copyWith(assignments: assignments);
    await ref.read(monthPlanRepositoryProvider).save(state);
    await _record(title, before);
    return true;
  }

  Future<void> setLocked(bool locked) async {
    if (!locked) ref.read(unlockedPastMonthsProvider.notifier).add(state.key);
    state = state.copyWith(isLocked: locked);
    await ref.read(monthPlanRepositoryProvider).save(state);
  }

  /// Önceki ayın son 6 gününün nöbetçileri (ay sınırında art arda gün ve
  /// gün aşırı zincir kuralları için).
  List<Set<String>> previousMonthTail() =>
      previousMonthTailOf(ref.read(monthPlanRepositoryProvider), state);
}

/// [plan]dan önceki ayın son 6 gününün nöbetçileri, eskiden yeniye.
List<Set<String>> previousMonthTailOf(
  MonthPlanRepository repository,
  MonthPlan plan,
) {
  final prev = DateTime(plan.year, plan.month - 1);
  final previous = repository.get(prev.year, prev.month);
  if (previous == null || !previous.hasRoster) return const [];
  final last = previous.daysInMonth;
  return [
    // Son 6 gün: 5 günlük boşluk sınırı ay geçişinde de denetlensin
    // (art arda gün ve gün aşırı zincir için son 4 gün yeterdi).
    for (var d = last - 5; d <= last; d++)
      {...?previous.assignments[d]?.personIds},
  ];
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
    blockReasons: ref.watch(blockReasonsProvider),
    previousMonthTail: ref.read(monthPlanProvider.notifier).previousMonthTail(),
    overtimeRequests: plan.overtimeRequests,
    requestedShifts: plan.requestedShifts,
    radiationReturnDays: computeRadiationReturnDays(
      plan,
      ref.watch(holidaysProvider),
      repository: ref.read(monthPlanRepositoryProvider),
    ),
    absentDays: plan.leaveDays,
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

/// [plan] ayında kişi → kapalı gün → neden: istemediği günler, izinler
/// (yıllık, şua, rapor), yıllık izin öncesi/sonrası kuralları (komşu
/// aylardaki izinler dahil) ve pasif günler.
Map<String, Map<int, BlockReason>> computeBlockReasons(
  MonthPlan plan,
  Iterable<Holiday> holidays, {
  MonthPlanRepository? repository,
  Iterable<Person> people = const [],
}) {
  final (plans, allHolidays) = _withNeighbours(plan, holidays, repository);

  final annualIds = {for (final p in plans) ...p.annualLeave.keys};
  Map<String, Set<int>> annualRule({required bool before}) => {
    for (final id in annualIds)
      id: LeaveRules.blockedDaysInMonth(
        year: plan.year,
        month: plan.month,
        annualLeave: [
          for (final p in plans)
            for (final d in p.annualLeaveOf(id)) DateTime(p.year, p.month, d),
        ],
        holidays: allHolidays,
        before: before,
        after: !before,
      ),
  };

  final radiationIds = {for (final p in plans) ...p.radiationLeave.keys};
  List<DateTime> radiationDates(String id) => [
    for (final p in plans)
      for (final d in p.leaveOf(id, LeaveType.radiation))
        DateTime(p.year, p.month, d),
  ];

  return BlockReason.combine({
    BlockReason.annualLeave: plan.leaveMap(LeaveType.annual),
    BlockReason.radiationLeave: plan.leaveMap(LeaveType.radiation),
    BlockReason.sickLeave: plan.leaveMap(LeaveType.sick),
    BlockReason.inactive: {
      for (final p in people) p.id: p.inactiveDaysIn(plan.year, plan.month),
    },
    BlockReason.unavailable: plan.unavailableDays,
    BlockReason.beforeAnnualLeave: annualRule(before: true),
    BlockReason.afterAnnualLeave: annualRule(before: false),
    BlockReason.beforeRadiationLeave: {
      for (final id in radiationIds)
        id: LeaveRules.radiationBlockedDaysInMonth(
          year: plan.year,
          month: plan.month,
          radiationLeave: radiationDates(id),
        ),
    },
    // Şua dönüşü yıllık izin gibi: ilk iş gününe kadar nöbet yok.
    BlockReason.afterRadiationLeave: {
      for (final id in radiationIds)
        id: LeaveRules.blockedDaysInMonth(
          year: plan.year,
          month: plan.month,
          annualLeave: radiationDates(id),
          holidays: allHolidays,
          before: false,
        ),
    },
  });
}

/// [plan] ile komşu ayların planları (izin kuralları ay sınırını aşar) ve
/// komşu yılların tatilleri dahil tatiller.
(List<MonthPlan>, List<Holiday>) _withNeighbours(
  MonthPlan plan,
  Iterable<Holiday> holidays,
  MonthPlanRepository? repository,
) {
  final prevMonth = DateTime(plan.year, plan.month - 1);
  final nextMonth = DateTime(plan.year, plan.month + 1);
  final plans = [
    plan,
    ?repository?.get(prevMonth.year, prevMonth.month),
    ?repository?.get(nextMonth.year, nextMonth.month),
  ];

  // Komşu ay başka yıldaysa ve o yılın tatilleri henüz yüklenmediyse
  // hazır Türkiye tatilleri kullanılır.
  final allHolidays = [...holidays];
  for (final year in {prevMonth.year, nextMonth.year}) {
    if (!allHolidays.any((h) => h.date.year == year)) {
      allHolidays.addAll(TurkishHolidays.forYear(year));
    }
  }
  return (plans, allHolidays);
}

/// [plan] ayında kişi → şua izni dönüşünün ilk iş günü (komşu aylardaki
/// şua dahil); kişi bu günde mutlaka nöbet tutar.
Map<String, Set<int>> computeRadiationReturnDays(
  MonthPlan plan,
  Iterable<Holiday> holidays, {
  MonthPlanRepository? repository,
}) {
  final (plans, allHolidays) = _withNeighbours(plan, holidays, repository);
  final result = <String, Set<int>>{};
  for (final id in {for (final p in plans) ...p.radiationLeave.keys}) {
    final days = LeaveRules.radiationReturnDaysInMonth(
      year: plan.year,
      month: plan.month,
      radiationLeave: [
        for (final p in plans)
          for (final d in p.leaveOf(id, LeaveType.radiation))
            DateTime(p.year, p.month, d),
      ],
      holidays: allHolidays,
    );
    if (days.isNotEmpty) result[id] = days;
  }
  return result;
}

/// [plan] ayında kişi → mutlaka nöbet tutacağı günler: plandaki istenen
/// nöbet günleri (sorumlu hemşire) ve şua izni dönüşünün ilk iş günü.
/// İstemediği günler üretici tarafından yine yazılmaz.
Map<String, List<int>> computeRequiredShifts(
  MonthPlan plan,
  Iterable<Holiday> holidays, {
  MonthPlanRepository? repository,
}) {
  final returns = computeRadiationReturnDays(
    plan,
    holidays,
    repository: repository,
  );
  return {
    for (final id in {...plan.requestedShifts.keys, ...returns.keys})
      id: {...?plan.requestedShifts[id], ...?returns[id]}.toList()..sort(),
  };
}

/// [plan] ayında kişi → nöbet yazılamayan günler (sıralı); nedenleri
/// [computeBlockReasons] verir.
Map<String, List<int>> computeEffectiveBlockedDays(
  MonthPlan plan,
  Iterable<Holiday> holidays, {
  MonthPlanRepository? repository,
  Iterable<Person> people = const [],
}) => BlockReason.days(
  computeBlockReasons(plan, holidays, repository: repository, people: people),
);

/// Seçili ayın 7A (gündüz mesaisi) planı: sorumlu hemşire ya da yerine
/// çalışan hemşire. Liste yoksa boş.
final dayShiftsProvider = Provider<Map<int, DayShift>>((ref) {
  final plan = ref.watch(monthPlanProvider);
  if (!plan.hasRoster) return const {};
  final tail = ref.read(monthPlanProvider.notifier).previousMonthTail();
  return DayShiftPlanner.plan(
    year: plan.year,
    month: plan.month,
    assignments: plan.assignments,
    people: ref.watch(peopleProvider),
    holidays: ref.watch(holidaysProvider),
    settings: ref.watch(effectiveSettingsProvider),
    leaveDays: plan.leaveDays,
    unavailableDays: plan.unavailableDays,
    previousMonthLastDay: tail.isEmpty ? const {} : tail.last,
    overrides: plan.dayShiftOverrides,
  );
});

/// Geçmiş kutusu her yazıldığında artar; [rosterHistoryProvider] yeniden
/// okunur. (Plan denetleyicisi geçmiş sağlayıcısını doğrudan yenileyemez:
/// geçmiş plana bağlıdır.)
class RosterHistoryVersion extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}

final rosterHistoryVersionProvider =
    NotifierProvider<RosterHistoryVersion, int>(RosterHistoryVersion.new);

/// Seçili ayın liste değişiklik geçmişi, eskiden yeniye.
final rosterHistoryProvider = Provider<List<RosterEdit>>((ref) {
  ref.watch(rosterHistoryVersionProvider);
  final plan = ref.watch(monthPlanProvider);
  return ref.watch(rosterHistoryRepositoryProvider).load(plan.year, plan.month);
});

/// Seçili ayın kapalı günleri ve nedenleri.
final blockReasonsProvider = Provider<Map<String, Map<int, BlockReason>>>((
  ref,
) {
  final plan = ref.watch(monthPlanProvider);
  final holidays = ref.watch(holidaysProvider);
  return computeBlockReasons(
    plan,
    holidays,
    repository: ref.read(monthPlanRepositoryProvider),
    people: ref.watch(peopleProvider),
  );
});

/// Seçili ayın etkin bloklu günleri. Üretim, uygunluk ve doğrulama kullanır.
final effectiveBlockedDaysProvider = Provider<Map<String, List<int>>>(
  (ref) => BlockReason.days(ref.watch(blockReasonsProvider)),
);

/// Seçili ay için liste oluşturmadan önceki uygunluk kontrolü.
final monthFeasibilityProvider = Provider<FeasibilityReport>((ref) {
  final plan = ref.watch(monthPlanProvider);
  return FeasibilityChecker(ref.watch(rosterSettingsProvider)).check(
    year: plan.year,
    month: plan.month,
    people: ref.watch(peopleProvider),
    unavailableDays: ref.watch(effectiveBlockedDaysProvider),
    requestedShifts: plan.requestedShifts,
  );
});
