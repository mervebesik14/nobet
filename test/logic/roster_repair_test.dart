import 'package:flutter_test/flutter_test.dart';
import 'package:nobet_listesi/logic/roster_repair.dart';
import 'package:nobet_listesi/logic/roster_validator.dart';
import 'package:nobet_listesi/models/models.dart';

/// 7 hemşire (n0–n6) + yedek Hale (n7, hiç nöbeti yok) + 4 tekniker.
List<Person> people({bool haleCharge = false}) => [
  for (var i = 0; i < 7; i++)
    Person(id: 'n$i', name: 'Hemşire $i', role: Role.nurse),
  Person(id: 'n7', name: 'Hale', role: Role.nurse, isChargeNurse: haleCharge),
  for (var i = 0; i < 4; i++)
    Person(id: 't$i', name: 'Tekniker $i', role: Role.radiologyTech),
];

/// Kurala uygun dönüşüm: d günü hemşireler (2d, 2d+1) mod 7, tekniker d mod 4.
Map<int, DayAssignment> rotation() => {
  for (var d = 1; d <= 31; d++)
    d: DayAssignment(
      day: d,
      nurseIds: ['n${(2 * d) % 7}', 'n${(2 * d + 1) % 7}'],
      techId: 't${d % 4}',
    ),
};

/// Gün → o günün nöbetçileri (koltuk sırası önemsiz).
Map<int, Set<String>> byDay(Map<int, DayAssignment> a) => {
  for (final e in a.entries) e.key: e.value.personIds.toSet(),
};

void main() {
  const settings = RosterSettings();

  RosterRepairResult repair(
    String id,
    int from, {
    List<Person>? team,
    Map<String, List<int>> blocked = const {},
  }) => RosterRepair.removePerson(
    year: 2026,
    month: 10,
    assignments: rotation(),
    personId: id,
    fromDay: from,
    people: team ?? people(),
    settings: settings,
    blockedDays: blocked,
  );

  test('tarihten önceye dokunmaz, sonrasında kişiyi çıkarıp doldurur', () {
    final original = rotation();
    final r = repair('n0', 20);

    for (var d = 1; d < 20; d++) {
      expect(r.assignments[d], original[d], reason: 'gün $d');
    }
    final removedDays = [
      for (var d = 20; d <= 31; d++)
        if (original[d]!.includes('n0')) d,
    ];
    expect(removedDays, isNotEmpty);
    expect(r.removed, removedDays.length);
    expect(r.unfilledDays, isEmpty);
    for (var d = 20; d <= 31; d++) {
      final a = r.assignments[d]!;
      expect(a.includes('n0'), isFalse, reason: 'gün $d');
      expect(a.nurseIds.length, 2, reason: 'gün $d');
      // Diğer kişilerin nöbetleri yerinde: yalnızca ekleme yapılır.
      for (final id in original[d]!.personIds) {
        if (id != 'n0') expect(a.includes(id), isTrue, reason: '$id gün $d');
      }
    }
    // Sonuç kurallara uygun.
    final violations = const RosterValidator(settings).validate(
      year: 2026,
      month: 10,
      assignments: r.assignments,
      people: people(),
    );
    expect(violations, isEmpty, reason: violations.join('\n'));
  });

  test('sorumlu hemşire boşalan koltuğa hiç yazılmaz', () {
    // Hale normalde (en az nöbetli olduğu için) seçilir; sorumlu
    // hemşireyse hiç seçilmez. Ondan başka kimsenin uymadığı gün boş kalır.
    final normal = repair('n0', 20);
    final charge = repair('n0', 20, team: people(haleCharge: true));
    expect(normal.replacements.values, contains('n7'));
    expect(charge.replacements.values, isNot(contains('n7')));
    expect(charge.unfilledDays, isNotEmpty);
    for (final d in charge.unfilledDays) {
      expect(normal.replacements[d], 'n7', reason: 'gün $d');
    }
  });

  test('en az nöbeti olan uygun kişi önce seçilir', () {
    // Hale'nin hiç nöbeti yok: kurala uyduğu ilk boşluğa o yazılır.
    final r = repair('n0', 20);
    expect(r.replacements.values, contains('n7'));
  });

  test('uygun kimse yoksa koltuk boş kalır', () {
    final original = rotation();
    final day = [
      for (var d = 20; d <= 31; d++)
        if (original[d]!.includes('n0')) d,
    ].first;
    final r = repair(
      'n0',
      day,
      blocked: {
        for (var i = 1; i <= 7; i++) 'n$i': [day],
      },
    );
    expect(r.unfilledDays, contains(day));
    expect(r.assignments[day]!.nurseIds.length, 1);
  });

  test('tekniker koltuğu teknikerle doldurulur', () {
    final r = repair('t0', 1);
    for (final MapEntry(key: d, value: id) in r.replacements.entries) {
      expect(id, startsWith('t'), reason: 'gün $d');
      expect(r.assignments[d]!.techId, id);
    }
    expect(r.assignments.values.any((a) => a.includes('t0')), isFalse);
  });

  group('geri verme', () {
    Map<int, String> handoversOf(RosterRepairResult r) => {
      ...r.replacements,
      for (final d in r.unfilledDays) d: '',
    };

    RosterRestoreResult restore(
      RosterRepairResult r, {
      Map<String, List<int>> blocked = const {},
    }) => RosterRestore.restorePerson(
      year: 2026,
      month: 10,
      assignments: r.assignments,
      personId: 'n0',
      role: Role.nurse,
      handovers: handoversOf(r),
      people: people(),
      settings: settings,
      blockedDays: blocked,
    );

    test('devredilen nöbetler geri verilince liste eski haline döner', () {
      final r = repair('n0', 20);
      final back = restore(r);
      expect(back.failedDays, isEmpty);
      expect(back.restoredDays.length, r.removed);
      expect(byDay(back.assignments), byDay(rotation()));
    });

    test('boş kalan koltuğa geri yazılır', () {
      final original = rotation();
      final day = [
        for (var d = 20; d <= 31; d++)
          if (original[d]!.includes('n0')) d,
      ].first;
      final r = repair(
        'n0',
        day,
        blocked: {
          for (var i = 1; i <= 7; i++) 'n$i': [day],
        },
      );
      expect(r.unfilledDays, contains(day));
      final back = restore(r);
      expect(back.restoredDays, contains(day));
      expect(back.assignments[day]!.includes('n0'), isTrue);
    });

    test('kişi o gün uygun değilse geri verilmez', () {
      final r = repair('n0', 20);
      final day = r.replacements.keys.first;
      final back = restore(
        r,
        blocked: {
          'n0': [day],
        },
      );
      expect(back.failedDays, [day]);
      expect(back.assignments[day]!.includes('n0'), isFalse);
    });
  });
}
