import 'package:flutter_test/flutter_test.dart';
import 'package:nobet_listesi/data/turkish_holidays.dart';
import 'package:nobet_listesi/logic/roster_generator.dart';
import 'package:nobet_listesi/models/models.dart';

/// Yıllar arası bayram adaleti: geçen Kurban'da tutanlar bu Kurban'da en
/// sona kalır; ay içi denge yine korunur.
void main() {
  final people = [
    for (var i = 1; i <= 6; i++)
      Person(id: 'n$i', name: 'Hemşire $i', role: Role.nurse),
    for (var i = 1; i <= 4; i++)
      Person(id: 't$i', name: 'Tekniker $i', role: Role.radiologyTech),
  ];
  // 2027 Kurban Bayramı: 16–19 Mayıs (4 tam gün).
  const kurban = [16, 17, 18, 19];

  Map<String, int> kurbanShifts(RosterResult r) {
    final counts = <String, int>{};
    for (final d in kurban) {
      for (final id in r.assignments[d]!.personIds) {
        counts[id] = (counts[id] ?? 0) + 1;
      }
    }
    return counts;
  }

  RosterResult run(int seed, Map<int, Set<String>> last) => RosterGenerator(
    year: 2027,
    month: 5,
    people: people,
    holidays: TurkishHolidays.forYear(2027),
    seed: seed,
    attempts: 60,
    previousHolidayWorkers: last,
  ).generate();

  test('geçen Kurban\'da tutan hemşire ve tekniker bu kez az tutar', () {
    final last = {
      for (final d in kurban) d: {'n1', 'n2', 't1'},
    };
    for (final seed in [1, 2, 3]) {
      final r = run(seed, last);
      final c = kurbanShifts(r);
      // 8 hemşire koltuğu / 6 kişi: n1 ve n2 birer, diğerleri 1–2.
      expect(
        (c['n1'] ?? 0) + (c['n2'] ?? 0),
        lessThanOrEqualTo(2),
        reason: 'seed $seed: $c',
      );
      expect(c['t1'] ?? 0, lessThanOrEqualTo(1), reason: 'seed $seed: $c');
      // Ay içi bayram dengesi bozulmaz (fark ≤ 1).
      final nurses = [for (var i = 1; i <= 6; i++) c['n$i'] ?? 0];
      expect(
        nurses.reduce((a, b) => a > b ? a : b) -
            nurses.reduce((a, b) => a < b ? a : b),
        lessThanOrEqualTo(1),
      );
    }
  });
}
