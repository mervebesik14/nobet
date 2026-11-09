import '../models/models.dart';

/// Bir kişinin deneme öncesi/sonrası yükü.
typedef LoadChange = ({
  String personId,
  String name,
  int shiftsBefore,
  int shiftsAfter,
  int weekendBefore,
  int weekendAfter,
});

/// "Ya şöyle olursa" denemesinin özeti (saf Dart): kaç nöbet değişti ve
/// kimin yükü arttı/azaldı.
class WhatIfReport {
  const WhatIfReport({required this.changedSeats, required this.loads});

  /// Değişen koltuk sayısı (yeni yazılan kişi başına).
  final int changedSeats;

  /// Nöbet ya da hafta sonu sayısı değişenler; en çok artan önce.
  final List<LoadChange> loads;

  static WhatIfReport compare({
    required Map<int, DayAssignment> before,
    required Map<int, DayAssignment> after,
    required Iterable<Person> people,
    Set<int> weekendDays = const {},
  }) {
    var changed = 0;
    for (final MapEntry(key: d, value: a) in after.entries) {
      final was = before[d]?.personIds ?? const <String>[];
      changed += a.personIds.where((id) => !was.contains(id)).length;
    }
    Set<int> daysOf(Map<int, DayAssignment> a, String id) => {
      for (final x in a.values)
        if (x.includes(id)) x.day,
    };
    final loads = <LoadChange>[];
    for (final p in people) {
      final b = daysOf(before, p.id), a = daysOf(after, p.id);
      final wb = b.where(weekendDays.contains).length;
      final wa = a.where(weekendDays.contains).length;
      if (b.length == a.length && wb == wa) continue;
      loads.add((
        personId: p.id,
        name: p.name,
        shiftsBefore: b.length,
        shiftsAfter: a.length,
        weekendBefore: wb,
        weekendAfter: wa,
      ));
    }
    loads.sort((x, y) {
      final dx = x.shiftsAfter - x.shiftsBefore;
      final dy = y.shiftsAfter - y.shiftsBefore;
      return dy != dx ? dy.compareTo(dx) : x.name.compareTo(y.name);
    });
    return WhatIfReport(changedSeats: changed, loads: loads);
  }

  /// "Banu: 8 → 9 nöbet (hafta sonu 2 → 3)"
  static String describe(LoadChange l) {
    final weekend = l.weekendBefore == l.weekendAfter
        ? ''
        : ' (hafta sonu ${l.weekendBefore} → ${l.weekendAfter})';
    return '${l.name}: ${l.shiftsBefore} → ${l.shiftsAfter} nöbet$weekend';
  }
}
