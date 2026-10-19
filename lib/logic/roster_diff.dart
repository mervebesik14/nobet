import '../models/day_assignment.dart';
import 'turkish_dates.dart';

/// İki liste arasındaki farkı okunur satırlara çevirir (saf Dart):
/// "3 Ekim: Ayşe yerine Hale", "4 Ekim: Banu çıkarıldı", "5 Ekim: Hale
/// eklendi", "7A 9 Ekim: Ayşe yerine Hale".
class RosterDiff {
  const RosterDiff._();

  static List<String> describe({
    required int month,
    required Map<int, DayAssignment> before,
    required Map<int, DayAssignment> after,
    Map<int, String> overridesBefore = const {},
    Map<int, String> overridesAfter = const {},
    required String Function(String id) name,
  }) {
    final lines = <String>[];
    final days = {...before.keys, ...after.keys}.toList()..sort();
    for (final d in days) {
      final was = before[d]?.personIds ?? const <String>[];
      final now = after[d]?.personIds ?? const <String>[];
      final removed = [
        for (final id in was)
          if (!now.contains(id)) id,
      ];
      final added = [
        for (final id in now)
          if (!was.contains(id)) id,
      ];
      final date = formatDayMonth(d, month);
      final pairs = removed.length < added.length
          ? removed.length
          : added.length;
      for (var i = 0; i < pairs; i++) {
        lines.add('$date: ${name(removed[i])} yerine ${name(added[i])}');
      }
      for (final id in removed.skip(pairs)) {
        lines.add('$date: ${name(id)} çıkarıldı');
      }
      for (final id in added.skip(pairs)) {
        lines.add('$date: ${name(id)} eklendi');
      }
    }
    final overrideDays = {
      ...overridesBefore.keys,
      ...overridesAfter.keys,
    }.toList()..sort();
    for (final d in overrideDays) {
      final was = overridesBefore[d];
      final now = overridesAfter[d];
      if (was == now) continue;
      final date = formatDayMonth(d, month);
      lines.add(switch ((was, now)) {
        (null, final n?) => '7A $date: ${name(n)} yazıldı',
        (final w?, null) => '7A $date: ${name(w)} yerine otomatik seçim',
        (final w?, final n?) => '7A $date: ${name(w)} yerine ${name(n)}',
        _ => '7A $date',
      });
    }
    return lines;
  }
}
