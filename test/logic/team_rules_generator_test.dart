import 'package:flutter_test/flutter_test.dart';
import 'package:nobet_listesi/data/turkish_holidays.dart';
import 'package:nobet_listesi/logic/roster_generator.dart';
import 'package:nobet_listesi/logic/roster_validator.dart';
import 'package:nobet_listesi/models/models.dart';

void main() {
  final holidays = TurkishHolidays.forYear(2026);
  final people = [
    for (var i = 1; i <= 7; i++)
      Person(
        id: 'n$i',
        name: 'Hemşire $i',
        role: Role.nurse,
        seniority: switch (i) {
          3 => Seniority.novice,
          4 || 5 => Seniority.senior,
          _ => Seniority.normal,
        },
      ),
    for (var i = 1; i <= 4; i++)
      Person(id: 't$i', name: 'Tekniker $i', role: Role.radiologyTech),
  ];
  const settings = RosterSettings(
    pairRules: [
      PairRule(a: 'n1', b: 'n2'),
      PairRule(a: 'n6', b: 'n7', together: true),
    ],
  );

  for (final seed in [1, 2, 3]) {
    test('tohum $seed: ayrı çift aynı gün yok, yeni başlayan kıdemliyle', () {
      final r = RosterGenerator(
        year: 2026,
        month: 10,
        people: people,
        holidays: holidays,
        settings: settings,
        seed: seed,
      ).generate();
      expect(r.isComplete, isTrue, reason: r.issues.join('\n'));
      var together = 0;
      for (final a in r.assignments.values) {
        final ids = a.nurseIds;
        expect(
          ids.contains('n1') && ids.contains('n2'),
          isFalse,
          reason: '${a.day}',
        );
        if (ids.contains('n3')) {
          expect(
            ids.contains('n4') || ids.contains('n5'),
            isTrue,
            reason: '${a.day}: $ids',
          );
        }
        if (ids.contains('n6') && ids.contains('n7')) together++;
      }
      expect(together, greaterThanOrEqualTo(3));
      final v = const RosterValidator(settings).validate(
        year: 2026,
        month: 10,
        assignments: r.assignments,
        people: people,
      );
      expect(
        v.where(
          (x) =>
              x.kind == ViolationKind.pairApart ||
              x.kind == ViolationKind.noSenior,
        ),
        isEmpty,
      );
    });
  }

  test('denetleyici: ayrı çift ve kıdemsiz yeni başlayan', () {
    final v = const RosterValidator(settings).validate(
      year: 2026,
      month: 10,
      assignments: const {
        1: DayAssignment(day: 1, nurseIds: ['n1', 'n2'], techId: 't1'),
        2: DayAssignment(day: 2, nurseIds: ['n3', 'n6'], techId: 't2'),
        3: DayAssignment(day: 3, nurseIds: ['n3', 'n4'], techId: 't3'),
      },
      people: people,
    );
    final pair = v.where((x) => x.kind == ViolationKind.pairApart).toList();
    expect(pair.single.days, [1]);
    expect(pair.single.message, contains('Hemşire 1 ile Hemşire 2'));
    final senior = v.where((x) => x.kind == ViolationKind.noSenior).toList();
    expect(senior.single.days, [2]);
    expect(senior.single.message, contains('Yeni başlayan Hemşire 3'));
  });

  test('2 tekniker: ayrı çift 24 ve 16B olarak aynı güne düşmez', () {
    final r = RosterGenerator(
      year: 2026,
      month: 10,
      people: people,
      holidays: holidays,
      settings: const RosterSettings(
        techsPerDay: 2,
        pairRules: [PairRule(a: 't1', b: 't2')],
      ),
      seed: 1,
    ).generate();
    for (final a in r.assignments.values) {
      expect({a.techId, a.tech16bId}.containsAll({'t1', 't2'}), isFalse);
    }
  });
}
