import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../data/providers.dart';
import '../../logic/roster_generator.dart';
import '../../logic/roster_diff.dart';
import '../../logic/roster_repair.dart';
import '../../logic/turkish_collation.dart';
import '../../models/models.dart';
import '../holidays/holidays_controller.dart';
import '../month/month_plan_controller.dart';

/// Pasif yapma sonucunda listelerde yapılan değişiklikler.
class DeactivationReport {
  const DeactivationReport({
    this.refilled = 0,
    this.unfilled = const [],
    this.restored = 0,
    this.restoreFailed = 0,
  });

  /// Pasif dönemi kısaldığı/sonlandığı için kişiye geri verilen nöbetler.
  final int restored;

  /// Kural bozacağı için geri verilemeyen nöbetler.
  final int restoreFailed;

  /// Başkasına verilen nöbet sayısı.
  final int refilled;

  /// Uygun kimse bulunamadığı için boş kalan nöbet günleri.
  final List<DateTime> unfilled;

  /// Kaldırılan toplam nöbet.
  int get removed => refilled + unfilled.length;

  DeactivationReport add(MonthPlan plan, RosterRepairResult result) =>
      DeactivationReport(
        refilled: refilled + result.replacements.length,
        unfilled: [
          ...unfilled,
          for (final d in result.unfilledDays)
            DateTime(plan.year, plan.month, d),
        ],
        restored: restored,
        restoreFailed: restoreFailed,
      );

  DeactivationReport withRestore(int restored, int failed) =>
      DeactivationReport(
        refilled: refilled,
        unfilled: unfilled,
        restored: this.restored + restored,
        restoreFailed: restoreFailed + failed,
      );
}

/// Kişi listesinin durumu: tüm kişiler, Türkçe alfabe sırasıyla.
class PeopleController extends Notifier<List<Person>> {
  static const _uuid = Uuid();

  @override
  List<Person> build() => ref.watch(peopleRepositoryProvider).getAll();

  /// Yeni kişi ekler, kimliği üretir.
  Future<Person> add({
    required String name,
    required Role role,
    bool isActive = true,
    bool isChargeNurse = false,
  }) async {
    final person = Person(
      id: _uuid.v4(),
      name: _cleanName(name),
      role: role,
      isActive: isActive,
      isChargeNurse: isChargeNurse,
    );
    await _save(person);
    return person;
  }

  /// Var olan kişiyi günceller.
  Future<void> update(Person person) =>
      _save(person.copyWith(name: _cleanName(person.name)));

  /// Aynı adla (büyük/küçük harf ve boşluk farkı gözetmeden) başka bir kişi
  /// var mı? Düzenlenen kişinin kendisi [exceptId] ile hariç tutulur.
  bool isNameTaken(String name, {String? exceptId}) {
    final normalized = normalizeName(name);
    return state.any(
      (p) => p.id != exceptId && normalizeName(p.name) == normalized,
    );
  }

  /// Kişi herhangi bir ay planında (istenmeyen gün ya da nöbet) geçiyor mu?
  bool isReferenced(String personId) =>
      ref.read(monthPlanRepositoryProvider).isPersonReferenced(personId);

  /// Kişiyi kalıcı olarak siler. Ay planlarında geçiyorsa oradaki nöbetleri
  /// geçmiş kaydı olarak kalır ve listelerde "Silinmiş kişi" diye görünür.
  Future<void> delete(String personId) async {
    final repo = ref.read(peopleRepositoryProvider);
    // Önce durumdan çıkar: kaydırılan satır aynı karede listeden kalkmalı.
    state = state.where((p) => p.id != personId).toList();
    await repo.delete(personId);
    state = repo.getAll();
  }

  /// Kişiyi [from]–[until] arasında (iki gün dahil) pasif yapar; [until]
  /// boşsa dönem süresizdir. Kişi dönem dışında çalışır, dönem içinde
  /// nöbete yazılmaz; geçmiş listelerde adıyla kalır. Kayıtlı listelerdeki
  /// dönem içi nöbetleri kaldırılır ve boşalan koltuklar diğer kişileri en
  /// az etkileyecek şekilde doldurulur ([RosterRepair]). [from] verilmezse
  /// kişi tamamen pasif olur ve listelere dokunulmaz.
  Future<DeactivationReport> deactivate(
    String personId, {
    DateTime? from,
    DateTime? until,
  }) async {
    final repo = ref.read(peopleRepositoryProvider);
    final person = repo.getById(personId);
    if (person == null) return const DeactivationReport();
    final start = from == null
        ? null
        : DateTime(from.year, from.month, from.day);
    var end = start == null || until == null
        ? null
        : DateTime(until.year, until.month, until.day);
    if (start != null && end != null && end.isBefore(start)) end = start;
    await repo.save(
      person.copyWith(
        // Bitişi belli dönemden sonra kişi kendiliğinden yeniden aktif olur.
        isActive: end != null,
        inactiveFrom: start,
        inactiveUntil: end,
        clearInactiveFrom: start == null,
        clearInactiveUntil: end == null,
      ),
    );
    state = repo.getAll();
    if (start == null) return const DeactivationReport();

    // Dönem kısaldıysa artık dönem dışında kalan devirler geri verilir.
    final (restored, failed) = await _restoreHandovers(
      personId,
      (date) => date.isBefore(start) || (end != null && date.isAfter(end)),
    );
    final plans = ref.read(monthPlanRepositoryProvider);
    final holidays = ref.read(holidaysProvider);
    var report = const DeactivationReport().withRestore(restored, failed);
    for (final plan in plans.getAll()) {
      // Yalnızca pasif dönemiyle kesişen ayların listesi onarılır.
      if (!plan.hasRoster ||
          DateTime(plan.year, plan.month + 1, 0).isBefore(start) ||
          (end != null && DateTime(plan.year, plan.month).isAfter(end))) {
        continue;
      }
      final fromDay = plan.year == start.year && plan.month == start.month
          ? start.day
          : 1;
      final toDay =
          end != null && plan.year == end.year && plan.month == end.month
          ? end.day
          : plan.daysInMonth;
      if (!plan.assignments.values.any(
        (a) => a.day >= fromDay && a.day <= toDay && a.includes(personId),
      )) {
        continue;
      }
      final settings = effectiveSettings(
        ref.read(rosterSettingsProvider),
        nurseOnly: plan.nurseOnly,
      );
      final result = RosterRepair.removePerson(
        year: plan.year,
        month: plan.month,
        assignments: plan.assignments,
        personId: personId,
        fromDay: fromDay,
        toDay: toDay,
        people: state,
        settings: settings,
        blockedDays: computeEffectiveBlockedDays(
          plan,
          holidays,
          repository: plans,
          people: state,
        ),
        weekendDays: RosterGenerator.weekendDays(
          plan.year,
          plan.month,
          holidays,
          settings,
        ),
        previousMonthTail: previousMonthTailOf(plans, plan),
        overtimeRequests: plan.overtimeRequests,
        requestedShifts: plan.requestedShifts,
        absentDays: plan.leaveDays,
      );
      await _recordHistory(
        plan,
        result.assignments,
        '${person.name} pasife alındı',
      );
      // Kime devredildiği, dönem kısalırsa geri vermek için saklanır.
      await plans.save(
        plan.copyWith(
          assignments: result.assignments,
          handovers: {
            ...plan.handovers,
            for (final MapEntry(key: d, value: id)
                in result.replacements.entries)
              MonthPlan.handoverKey(personId, d): id,
            for (final d in result.unfilledDays)
              MonthPlan.handoverKey(personId, d): '',
          },
        ),
      );
      report = report.add(plan, result);
    }
    // Açık ayın planı yeniden okunsun.
    ref.invalidate(monthPlanProvider);
    return report;
  }

  /// Pasif dönemini sonlandırır: kişi [activeFrom] gününden itibaren yeniden
  /// aktif olur. Dönemin o güne kadarki kısmı kayıtta kalır (geçmiş aylar
  /// doğru kalsın diye); dönem henüz başlamadıysa tamamen silinir. O günden
  /// sonraki, başkalarına devredilmiş nöbetleri kurala uyuyorsa ona geri
  /// verilir.
  Future<DeactivationReport> endInactivity(
    String personId, {
    required DateTime activeFrom,
  }) async {
    final repo = ref.read(peopleRepositoryProvider);
    final person = repo.getById(personId);
    if (person == null) return const DeactivationReport();
    final from = person.inactiveFrom;
    final start = DateTime(activeFrom.year, activeFrom.month, activeFrom.day);
    final lastInactive = DateTime(start.year, start.month, start.day - 1);
    if (from == null ||
        lastInactive.isBefore(DateTime(from.year, from.month, from.day))) {
      await activate(personId);
    } else {
      await repo.save(
        person.copyWith(isActive: true, inactiveUntil: lastInactive),
      );
      state = repo.getAll();
    }
    // Yeniden aktif olduğu günden sonraki devirler geri verilir.
    final (restored, failed) = await _restoreHandovers(
      personId,
      (date) => !date.isBefore(start),
    );
    return const DeactivationReport().withRestore(restored, failed);
  }

  /// Pasife alma / geri vermenin listede yaptığı değişikliği o ayın
  /// geçmişine yazar (geri alınabilsin diye). Fark yoksa yazmaz.
  Future<void> _recordHistory(
    MonthPlan plan,
    Map<int, DayAssignment> after,
    String title,
  ) async {
    final names = {for (final p in state) p.id: p.name};
    final lines = RosterDiff.describe(
      month: plan.month,
      before: plan.assignments,
      after: after,
      name: (id) => names[id] ?? 'Silinmiş kişi',
    );
    if (lines.isEmpty) return;
    await ref
        .read(rosterHistoryRepositoryProvider)
        .add(
          plan.year,
          plan.month,
          RosterEdit(
            at: DateTime.now(),
            title: title,
            lines: lines,
            before: plan.assignments,
            beforeOverrides: plan.dayShiftOverrides,
            beforeGeneratedAt: plan.generatedAt,
            beforeSeed: plan.seed,
          ),
        );
    ref.read(rosterHistoryVersionProvider.notifier).bump();
  }

  /// Kişinin [shouldRestore] günlerindeki devredilmiş nöbetlerini, kurala
  /// uyuyorsa geri verir; işlenen devir kayıtları silinir. (geri verilen,
  /// verilemeyen) sayılarını döndürür.
  Future<(int, int)> _restoreHandovers(
    String personId,
    bool Function(DateTime date) shouldRestore,
  ) async {
    final person = ref.read(peopleRepositoryProvider).getById(personId);
    if (person == null) return (0, 0);
    final plans = ref.read(monthPlanRepositoryProvider);
    final holidays = ref.read(holidaysProvider);
    var restored = 0;
    var failed = 0;
    for (final plan in plans.getAll()) {
      final handovers = {
        for (final e in plan.handoversOf(personId).entries)
          if (shouldRestore(DateTime(plan.year, plan.month, e.key)))
            e.key: e.value,
      };
      if (handovers.isEmpty) continue;
      final result = RosterRestore.restorePerson(
        year: plan.year,
        month: plan.month,
        assignments: plan.assignments,
        personId: personId,
        role: person.role,
        handovers: handovers,
        people: state,
        settings: effectiveSettings(
          ref.read(rosterSettingsProvider),
          nurseOnly: plan.nurseOnly,
        ),
        blockedDays: computeEffectiveBlockedDays(
          plan,
          holidays,
          repository: plans,
          people: state,
        ),
        previousMonthTail: previousMonthTailOf(plans, plan),
        overtimeRequests: plan.overtimeRequests,
        requestedShifts: plan.requestedShifts,
      );
      await _recordHistory(
        plan,
        result.assignments,
        '${person.name} nöbetlerini geri aldı',
      );
      await plans.save(
        plan.copyWith(
          assignments: result.assignments,
          handovers: {
            for (final e in plan.handovers.entries)
              if (!handovers.keys.any(
                (d) => e.key == MonthPlan.handoverKey(personId, d),
              ))
                e.key: e.value,
          },
        ),
      );
      restored += result.restoredDays.length;
      failed += result.failedDays.length;
    }
    if (restored + failed > 0) ref.invalidate(monthPlanProvider);
    return (restored, failed);
  }

  /// Pasif kişiyi yeniden aktif yapar (pasif başlangıcı silinir).
  Future<void> activate(String personId) async {
    final repo = ref.read(peopleRepositoryProvider);
    final person = repo.getById(personId);
    if (person == null) return;
    await repo.save(person.copyWith(isActive: true, clearInactiveFrom: true));
    state = repo.getAll();
  }

  Future<void> _save(Person person) async {
    final repo = ref.read(peopleRepositoryProvider);
    // Sorumlu hemşire yalnızca hemşire olabilir ve tek kişidir: yenisi
    // işaretlenince öncekinin işareti kalkar.
    final saved = person.role == Role.nurse
        ? person
        : person.copyWith(isChargeNurse: false);
    if (saved.isChargeNurse) {
      for (final other in repo.getAll()) {
        if (other.id != saved.id && other.isChargeNurse) {
          await repo.save(other.copyWith(isChargeNurse: false));
        }
      }
    }
    await repo.save(saved);
    state = repo.getAll();
  }

  /// Aktif sorumlu hemşire (yoksa null).
  Person? get chargeNurse {
    for (final p in state) {
      if (p.isActive && p.isChargeNurse && p.role == Role.nurse) return p;
    }
    return null;
  }

  static String _cleanName(String name) =>
      name.trim().replaceAll(RegExp(r'\s+'), ' ');
}

final peopleProvider = NotifierProvider<PeopleController, List<Person>>(
  PeopleController.new,
);
