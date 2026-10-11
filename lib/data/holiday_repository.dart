import 'package:hive_ce/hive_ce.dart';

import '../models/models.dart';

/// Tatilleri saklar; anahtar `yyyy-MM-dd`, yani bir güne tek tatil düşer.
class HolidayRepository {
  HolidayRepository(this._box);

  final Box<Holiday> _box;

  /// Tüm tatiller, tarihe göre sıralı.
  List<Holiday> getAll() =>
      _box.values.toList()..sort((a, b) => a.date.compareTo(b.date));

  List<Holiday> getForMonth(int year, int month) => getAll()
      .where((h) => h.date.year == year && h.date.month == month)
      .toList();

  Holiday? getByDate(DateTime date) => _box.get(Holiday.keyFor(date));

  bool get isEmpty => _box.isEmpty;

  /// Aynı güne kayıtlı tatil varsa üzerine yazar.
  Future<void> save(Holiday holiday) => _box.put(holiday.key, holiday);

  Future<void> saveAll(Iterable<Holiday> holidays) =>
      _box.putAll({for (final h in holidays) h.key: h});

  Future<void> delete(DateTime date) => _box.delete(Holiday.keyFor(date));

  Stream<BoxEvent> watch() => _box.watch();
}
