import 'package:flutter_test/flutter_test.dart';
import 'package:nobet_listesi/data/turkish_holidays.dart';
import 'package:nobet_listesi/logic/day_shift_planner.dart';
import 'package:nobet_listesi/models/models.dart';

void main() {
  // Ekim 2026: 1 Per ... 5, 12, 19, 26 Pazartesi; 28 Çar arife (yarım gün),
  // 29 Per Cumhuriyet Bayramı (tam gün). Mesai günleri: 1, 2, 5–9, 12–16,
  // 19–23, 26, 27, 28, 30 → 21 gün.
  final holidays = TurkishHolidays.forYear(2026);
  const settings = RosterSettings();
  const workdays = [
    1, 2, 5, 6, 7, 8, 9, 12, 13, 14, 15, 16, //
    19, 20, 21, 22, 23, 26, 27, 28, 30,
  ];

  const charge = Person(
    id: 'c',
    name: 'Sorumlu',
    role: Role.nurse,
    isChargeNurse: true,
  );
  final nurses = [
    for (var i = 1; i <= 7; i++)
      Person(id: 'n$i', name: 'Hemşire $i', role: Role.nurse),
  ];

  Map<int, DayShift> plan({
    List<Person>? people,
    Map<int, DayAssignment> assignments = const {},
    Map<String, List<int>> leave = const {},
    Map<String, List<int>> unavailable = const {},
    Set<String> tail = const {},
  }) => DayShiftPlanner.plan(
    year: 2026,
    month: 10,
    assignments: assignments,
    people: people ?? [charge, ...nurses],
    holidays: holidays,
    settings: settings,
    leaveDays: leave,
    unavailableDays: unavailable,
    previousMonthLastDay: tail,
  );

  test('sorumlu hemşire yoksa 7A yok', () {
    expect(plan(people: nurses), isEmpty);
  });

  test('nöbeti yoksa her mesai günü sorumlu hemşire 7A; arife 5 saat', () {
    final p = plan();
    expect(p.keys.toList()..sort(), workdays);
    expect(p.values.every((s) => s.personId == 'c' && !s.isSubstitute), isTrue);
    expect(p[28]!.hours, 5);
    expect(p[27]!.hours, 7);
    // Hafta sonu ve tam gün tatilde 7A yok.
    expect(p.containsKey(3), isFalse);
    expect(p.containsKey(29), isFalse);
  });

  test('nöbet günü ve nöbet ertesi başka hemşire 7A çalışır', () {
    // Sorumlu 6 Ekim Salı nöbetçi: 6'da ve 7'de (nöbet ertesi) yerine biri.
    final p = plan(
      assignments: {
        6: const DayAssignment(day: 6, nurseIds: ['c', 'n1']),
        5: const DayAssignment(day: 5, nurseIds: ['n2', 'n3']),
      },
    );
    expect(p[5]!.personId, 'c');
    for (final d in [6, 7]) {
      expect(p[d]!.isSubstitute, isTrue, reason: 'gün $d');
      expect(p[d]!.personId, isNot('c'));
    }
    expect(p[8]!.personId, 'c');
    // 6'da nöbetçi n1 ve 5'te nöbetçi (6'da nöbet ertesi) n2, n3 olamaz.
    expect(['n1', 'n2', 'n3'], isNot(contains(p[6]!.personId)));
    // 7'de n1 nöbet ertesi; olamaz.
    expect(p[7]!.personId, isNot('n1'));
  });

  test('izinli günlerde yerine başkası; yerine geçme eşit dağılır', () {
    // Sorumlu ay boyu izinli: 21 mesai günü 7 hemşireye 3'er düşer.
    final p = plan(
      leave: {
        'c': [for (var d = 1; d <= 31; d++) d],
      },
    );
    expect(p.length, 21);
    final counts = <String, int>{};
    for (final s in p.values) {
      expect(s.isSubstitute, isTrue);
      counts[s.personId] = (counts[s.personId] ?? 0) + 1;
    }
    expect(counts.values.toSet(), {3});
  });

  test('istemediği gün ve izinli hemşire yerine geçmez', () {
    final p = plan(
      leave: {
        'c': [14],
        'n1': [14],
      },
      unavailable: {
        'n2': [14],
      },
    );
    expect(['c', 'n1', 'n2'], isNot(contains(p[14]!.personId)));
  });

  test('sorumlu hemşirenin istemediği gün 7A\'sını etkilemez', () {
    final p = plan(
      unavailable: {
        'c': [14],
      },
    );
    expect(p[14]!.personId, 'c');
  });

  test('önceki ayın son günü nöbetçiyse 1\'inde dinlenir', () {
    final p = plan(tail: {'c'});
    expect(p[1]!.isSubstitute, isTrue);
    expect(p[2]!.personId, 'c');
  });
}
