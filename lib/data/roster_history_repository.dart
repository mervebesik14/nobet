import 'dart:convert';

import 'package:hive_ce/hive_ce.dart';

import '../models/models.dart';

/// Ay ay nöbet listesi değişiklik geçmişi. Her ay için en fazla
/// [maxEntries] kayıt tutulur (en eskiler silinir).
class RosterHistoryRepository {
  RosterHistoryRepository(this._box);

  static const maxEntries = 50;

  final Box<dynamic> _box;

  /// Eskiden yeniye.
  List<RosterEdit> load(int year, int month) {
    final raw = _box.get(MonthPlan.keyFor(year, month));
    if (raw is! List) return const [];
    return [
      for (final s in raw.whereType<String>())
        RosterEdit.fromJson((jsonDecode(s) as Map).cast<String, dynamic>()),
    ];
  }

  Future<void> _save(int year, int month, List<RosterEdit> edits) {
    final key = MonthPlan.keyFor(year, month);
    if (edits.isEmpty) return _box.delete(key);
    final kept = edits.length > maxEntries
        ? edits.sublist(edits.length - maxEntries)
        : edits;
    return _box.put(key, [for (final e in kept) jsonEncode(e.toJson())]);
  }

  Future<void> add(int year, int month, RosterEdit edit) =>
      _save(year, month, [...load(year, month), edit]);

  /// [index] ve sonrasındaki kayıtları siler (geri almada).
  Future<void> truncate(int year, int month, int index) =>
      _save(year, month, load(year, month).take(index).toList());

  Future<void> clear(int year, int month) => _save(year, month, const []);
}
