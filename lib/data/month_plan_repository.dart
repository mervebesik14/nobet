import 'package:hive_ce/hive_ce.dart';

import '../models/models.dart';

/// Ay planlarını saklar; anahtar `yyyy-MM`.
class MonthPlanRepository {
  MonthPlanRepository(this._box);

  final Box<MonthPlan> _box;

  /// Tüm planlar, eskiden yeniye.
  List<MonthPlan> getAll() =>
      _box.values.toList()..sort((a, b) => a.key.compareTo(b.key));

  MonthPlan? get(int year, int month) =>
      _box.get(MonthPlan.keyFor(year, month));

  /// Plan yoksa boş bir plan oluşturup kaydeder.
  Future<MonthPlan> getOrCreate(int year, int month) async {
    final existing = get(year, month);
    if (existing != null) return existing;
    final plan = MonthPlan(year: year, month: month);
    await save(plan);
    return plan;
  }

  Future<void> save(MonthPlan plan) => _box.put(plan.key, plan);

  Future<void> delete(int year, int month) =>
      _box.delete(MonthPlan.keyFor(year, month));

  /// Kişi herhangi bir planda geçiyor mu? Geçiyorsa silinmez, pasifleştirilir.
  bool isPersonReferenced(String personId) =>
      _box.values.any((plan) => plan.references(personId));

  Stream<BoxEvent> watch() => _box.watch();
}
