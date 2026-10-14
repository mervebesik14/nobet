import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../data/providers.dart';
import '../../logic/roster_generator.dart';
import '../../logic/roster_repair.dart';
import '../../logic/turkish_collation.dart';
import '../../models/models.dart';
import '../holidays/holidays_controller.dart';
import '../month/month_plan_controller.dart';

/// Pasif yapma sonucunda listelerde yapılan değişiklikler.
class DeactivationReport {
  const DeactivationReport({this.refilled = 0, this.unfilled = const []});

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

  /// Kişiyi [from] gününden itibaren pasif yapar: o günden önce çalışır,
  /// o günden itibaren nöbete yazılmaz; geçmiş listelerde adıyla kalır.
  /// Kayıtlı listelerdeki o günden sonraki nöbetleri kaldırılır ve boşalan
  /// koltuklar diğer kişileri en az etkileyecek şekilde doldurulur
  /// ([RosterRepair]). [from] verilmezse kişi tamamen pasif olur ve
  /// listelere dokunulmaz.
  Future<DeactivationReport> deactivate(
    String personId, {
    DateTime? from,
  }) async {
    final repo = ref.read(peopleRepositoryProvider);
    final person = repo.getById(personId);
    if (person == null) return const DeactivationReport();
    final start = from == null
        ? null
        : DateTime(from.year, from.month, from.day);
    await repo.save(
      person.copyWith(
        isActive: false,
        inactiveFrom: start,
        clearInactiveFrom: start == null,
      ),
    );
    state = repo.getAll();
    if (start == null) return const DeactivationReport();

    final plans = ref.read(monthPlanRepositoryProvider);
    final holidays = ref.read(holidaysProvider);
    var report = const DeactivationReport();
    for (final plan in plans.getAll()) {
      // Pasiflik gününden önce biten ayların listesine dokunulmaz.
      if (!plan.hasRoster ||
          DateTime(plan.year, plan.month + 1, 0).isBefore(start)) {
        continue;
      }
      final fromDay = plan.year == start.year && plan.month == start.month
          ? start.day
          : 1;
      if (!plan.assignments.values.any(
        (a) => a.day >= fromDay && a.includes(personId),
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
      );
      await plans.save(plan.copyWith(assignments: result.assignments));
      report = report.add(plan, result);
    }
    // Açık ayın planı yeniden okunsun.
    ref.invalidate(monthPlanProvider);
    return report;
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
