import 'package:flutter_test/flutter_test.dart';
import 'package:nobet_listesi/data/turkish_holidays.dart';
import 'package:nobet_listesi/logic/roster_editor.dart';
import 'package:nobet_listesi/logic/roster_generator.dart';
import 'package:nobet_listesi/logic/roster_summary.dart';
import 'package:nobet_listesi/logic/roster_validator.dart';
import 'package:nobet_listesi/models/models.dart';

List<Person> team(int nurses, int techs) => [
  for (var i = 1; i <= nurses; i++)
    Person(id: 'n$i', name: 'Hemşire $i', role: Role.nurse),
  for (var i = 1; i <= techs; i++)
    Person(id: 't$i', name: 'Tekniker $i', role: Role.radiologyTech),
];

int spread(Iterable<int> v) =>
    v.reduce((a, b) => a > b ? a : b) - v.reduce((a, b) => a < b ? a : b);

void main() {
  final holidays = TurkishHolidays.forYear(2026);
  const settings = RosterSettings(techsPerDay: 2);

  group('RosterGenerator: 2 tekniker (24 + 16B)', () {
    final people = team(7, 5);
    final weekend = RosterGenerator.weekendDays(2026, 10, holidays, settings);

    for (final seed in [1, 2, 3]) {
      test('tohum $seed: her gün 24+16B, kurallar ve adalet', () {
        final r = RosterGenerator(
          year: 2026,
          month: 10,
          people: people,
          holidays: holidays,
          settings: settings,
          seed: seed,
          attempts: 150,
        ).generate();
        expect(r.isComplete, isTrue, reason: r.issues.join('\n'));

        final c24 = <String, Set<int>>{};
        final c16 = <String, Set<int>>{};
        for (var d = 1; d <= 31; d++) {
          final a = r.assignments[d]!;
          expect(a.nurseIds.length, 2);
          expect(a.techId, isNotNull);
          expect(a.tech16bId, isNotNull);
          expect(a.techId, isNot(a.tech16bId));
          (c24[a.techId!] ??= {}).add(d);
          (c16[a.tech16bId!] ??= {}).add(d);
        }
        // 24 çalışan ertesi gün hiç çalışmaz; 16B çalışabilir.
        for (final e in c24.entries) {
          for (final d in e.value) {
            expect(c24[e.key]!.contains(d + 1), isFalse);
            expect(c16[e.key]?.contains(d + 1) ?? false, isFalse);
            // gün aşırı zincir yalnız 24'te, en fazla 2
            expect([d, d + 2, d + 4].every(e.value.contains), isFalse);
          }
        }
        // Adalet: 24 ve 16B ayrı ayrı ≤ 1, hafta sonu ≤ 1.
        final ids = [for (var i = 1; i <= 5; i++) 't$i'];
        expect(
          spread([for (final id in ids) (c24[id] ?? {}).length]),
          lessThanOrEqualTo(1),
        );
        expect(
          spread([for (final id in ids) (c16[id] ?? {}).length]),
          lessThanOrEqualTo(1),
        );
        expect(
          spread([
            for (final id in ids)
              (c24[id] ?? {}).where(weekend.contains).length +
                  (c16[id] ?? {}).where(weekend.contains).length,
          ]),
          lessThanOrEqualTo(1),
        );
      });
    }

    test('aynı tohum aynı sonuç', () {
      RosterResult gen() => RosterGenerator(
        year: 2026,
        month: 10,
        people: people,
        holidays: holidays,
        settings: settings,
        seed: 9,
        attempts: 60,
      ).generate();
      expect(gen().assignments, gen().assignments);
    });

    // Küçük ekipte her gün bir öncekine bağlı; tek koltuk hamleleri
    // takılıyordu. Ay içi fark yine de ≤ 1 olmalı.
    for (final (techs, month) in [(3, 5), (3, 3), (3, 1), (7, 5), (7, 6)]) {
      test('$techs tekniker, $month. ay: ay içi fark ≤ 1', () {
        final people = team(7, techs);
        final weekend = RosterGenerator.weekendDays(
          2026,
          month,
          holidays,
          settings,
        );
        for (final seed in [1, 2, 3]) {
          final r = RosterGenerator(
            year: 2026,
            month: month,
            people: people,
            holidays: holidays,
            settings: settings,
            seed: seed,
            attempts: 150,
          ).generate();
          expect(r.isComplete, isTrue, reason: r.issues.join('\n'));
          final ids = [for (var i = 1; i <= techs; i++) 't$i'];
          final c24 = {for (final id in ids) id: <int>{}};
          final c16 = {for (final id in ids) id: <int>{}};
          for (final a in r.assignments.values) {
            c24[a.techId]!.add(a.day);
            c16[a.tech16bId]!.add(a.day);
          }
          final measures = {
            '24': [for (final id in ids) c24[id]!.length],
            '16B': [for (final id in ids) c16[id]!.length],
            'hafta sonu': [
              for (final id in ids)
                {...c24[id]!, ...c16[id]!}.where(weekend.contains).length,
            ],
            'gün aşırı': [
              for (final id in ids)
                RosterGenerator.everyOtherDayPairs(c24[id]!),
            ],
          };
          for (final e in measures.entries) {
            expect(
              spread(e.value),
              lessThanOrEqualTo(1),
              reason: 'tohum $seed, ${e.key}: ${e.value}',
            );
          }
        }
      });
    }
  });

  group('RosterValidator: 24/16B kuralları', () {
    const people = [
      Person(id: 'a', name: 'Ali', role: Role.radiologyTech),
      Person(id: 'b', name: 'Veli', role: Role.radiologyTech),
      Person(id: 'n1', name: 'H1', role: Role.nurse),
      Person(id: 'n2', name: 'H2', role: Role.nurse),
    ];
    List<RuleViolation> check(Map<int, DayAssignment> a) =>
        const RosterValidator(
          settings,
        ).validate(year: 2027, month: 2, assignments: a, people: people);

    DayAssignment day(int d, String? t24, String? t16) => DayAssignment(
      day: d,
      nurseIds: const ['n1', 'n2'],
      techId: t24,
      tech16bId: t16,
    );

    test('24 çalışan ertesi gün çalışırsa ihlal', () {
      // a: 1'de 24, 2'de 16B → ihlal (24 sonrası ertesi gün).
      final v = check({
        1: day(1, 'a', 'b'),
        2: day(2, 'b', 'a'),
      }).where((x) => x.kind == ViolationKind.consecutive).toList();
      expect(v.map((x) => x.personId), contains('a'));
      expect(
        v.firstWhere((x) => x.personId == 'a').message,
        'Ali 1 ve 2 Şubat art arda nöbette.',
      );
    });

    test('16B çalışan ertesi gün çalışırsa ihlal yok', () {
      // b: 1'de 16B, 2'de 24 → serbest.
      final v = check({
        1: day(1, 'a', 'b'),
        2: day(2, 'b', 'a'),
      }).where((x) => x.kind == ViolationKind.consecutive && x.personId == 'b');
      expect(v, isEmpty);
    });

    test('gün aşırı zincir yalnız 24: 16B günleri sayılmaz', () {
      // a: 1,3,5 hepsi 16B → zincir ihlali yok.
      final a16 = {
        1: day(1, 'b', 'a'),
        3: day(3, 'b', 'a'),
        5: day(5, 'b', 'a'),
      };
      // a 16B olduğundan a'da zincir yok (b 24 olduğundan onda olabilir).
      expect(
        check(
          a16,
        ).where((x) => x.kind == ViolationKind.chain && x.personId == 'a'),
        isEmpty,
      );
      // a: 1,3,5 hepsi 24 → zincir ihlali var.
      final a24 = {
        1: day(1, 'a', 'b'),
        3: day(3, 'a', 'b'),
        5: day(5, 'a', 'b'),
      };
      expect(
        check(
          a24,
        ).where((x) => x.kind == ViolationKind.chain && x.personId == 'a'),
        isNotEmpty,
      );
    });

    test('eksik 24 ve 16B ayrı raporlanır', () {
      final v = check({1: day(1, null, null)})
          .where((x) => x.kind == ViolationKind.missing && x.days.single == 1)
          .map((x) => x.message)
          .toList();
      expect(
        v,
        containsAll([
          '1 Şubat: 24 teknikeri eksik.',
          '1 Şubat: 16B teknikeri eksik.',
        ]),
      );
    });
  });

  group('RosterSummary: 16B saatleri', () {
    const people = [
      Person(id: 't', name: 'Tekniker', role: Role.radiologyTech),
    ];
    test('çalışılan saat = 24*24 + 16B*16', () {
      // t: 3 gün 24, 2 gün 16B.
      final assignments = {
        1: const DayAssignment(day: 1, techId: 't'),
        3: const DayAssignment(day: 3, techId: 't'),
        5: const DayAssignment(day: 5, techId: 't'),
        7: const DayAssignment(day: 7, tech16bId: 't'),
        9: const DayAssignment(day: 9, tech16bId: 't'),
      };
      final s = RosterSummary.build(
        year: 2026,
        month: 10,
        assignments: assignments,
        people: people,
        holidays: holidays,
        settings: settings,
      );
      final row = s.people.single;
      expect(row.shifts, 5);
      expect(row.secondaryShifts, 2);
      expect(row.primaryShifts, 3);
      expect(row.workedHours, 3 * 24 + 2 * 16); // 104
    });
  });

  group('RosterEditor: 16B koltuğu', () {
    final base = {
      1: const DayAssignment(
        day: 1,
        nurseIds: ['n1', 'n2'],
        techId: 'a',
        tech16bId: 'b',
      ),
      2: const DayAssignment(
        day: 2,
        nurseIds: ['n3', 'n4'],
        techId: 'c',
        tech16bId: 'd',
      ),
    };

    test('16B koltuğunu değiştir', () {
      final r = RosterEditor.replace(
        base,
        day: 1,
        role: Role.radiologyTech,
        oldId: 'b',
        newId: 'e',
        nursesPerDay: 2,
        secondary: true,
      );
      expect(r[1]!.tech16bId, 'e');
      expect(r[1]!.techId, 'a');
    });

    test('24 ve 16B koltukları karışmaz', () {
      // b (16B) yerine 24 koltuğunda düzenlemeye çalışmak hata verir.
      expect(
        () => RosterEditor.replace(
          base,
          day: 1,
          role: Role.radiologyTech,
          oldId: 'b',
          newId: 'e',
          nursesPerDay: 2,
        ),
        throwsA(isA<RosterEditException>()),
      );
    });

    test('takasta herkes kendi koltuğunu korur', () {
      // a (24@1) ile d (16B@2) takas: a → 2 günün 16B, d → 1 günün 24.
      final r = RosterEditor.swap(
        base,
        a: 'a',
        dayA: 1,
        b: 'd',
        dayB: 2,
        role: Role.radiologyTech,
        nursesPerDay: 2,
      );
      expect(r[1]!.techId, 'd');
      expect(r[1]!.tech16bId, 'b');
      expect(r[2]!.techId, 'c');
      expect(r[2]!.tech16bId, 'a');
    });
  });

  group('şua dönüşü: ilk iş günü mutlaka nöbet', () {
    // Kasım 2026: şua 1–4 Kasım (4 Çarşamba), dönüş 5 Kasım Perşembe.
    const leave = [1, 2, 3, 4];
    for (final techsPerDay in [1, 2]) {
      test('günde $techsPerDay tekniker: tekniker 5 Kasım nöbette', () {
        for (final seed in [1, 2, 3, 4]) {
          final r = RosterGenerator(
            year: 2026,
            month: 11,
            people: team(7, 4),
            holidays: holidays,
            settings: RosterSettings(techsPerDay: techsPerDay),
            seed: seed,
            attempts: 60,
            unavailableDays: const {'t2': leave},
            absentDays: const {'t2': leave},
            requestedShifts: const {
              't2': [5],
            },
          ).generate();
          expect(r.isComplete, isTrue, reason: r.issues.join('\n'));
          expect(
            r.assignments[5]!.includes('t2'),
            isTrue,
            reason: 'seed $seed',
          );
          for (final d in leave) {
            expect(r.assignments[d]!.includes('t2'), isFalse);
          }
        }
      });
    }

    test('hemşire de 5 Kasım nöbette', () {
      for (final seed in [1, 2, 3]) {
        final r = RosterGenerator(
          year: 2026,
          month: 11,
          people: team(7, 4),
          holidays: holidays,
          seed: seed,
          attempts: 60,
          unavailableDays: const {'n3': leave},
          absentDays: const {'n3': leave},
          requestedShifts: const {
            'n3': [5],
          },
        ).generate();
        expect(
          r.assignments[5]!.nurseIds,
          contains('n3'),
          reason: 'seed $seed',
        );
      }
    });

    test('istemediği günse yazılmaz', () {
      final r = RosterGenerator(
        year: 2026,
        month: 11,
        people: team(7, 4),
        holidays: holidays,
        seed: 1,
        attempts: 30,
        unavailableDays: const {
          't2': [...leave, 5],
        },
        requestedShifts: const {
          't2': [5],
        },
      ).generate();
      expect(r.assignments[5]!.includes('t2'), isFalse);
    });
  });

  test('ay sonunda 5 günden uzun boşluk kalmaz', () {
    for (final (techsPerDay, month) in [(1, 9), (2, 11), (1, 6)]) {
      for (final seed in [1, 2, 3]) {
        final people = team(9, 5);
        final r = RosterGenerator(
          year: 2026,
          month: month,
          people: people,
          holidays: holidays,
          settings: RosterSettings(techsPerDay: techsPerDay),
          seed: seed,
          attempts: 100,
        ).generate();
        final days = DateTime(2026, month + 1, 0).day;
        for (final p in people) {
          final last = r.assignments.values
              .where((a) => a.includes(p.id))
              .map((a) => a.day)
              .fold(0, (a, b) => a > b ? a : b);
          expect(
            days - last,
            lessThanOrEqualTo(5),
            reason: '${p.id}, $month. ay, tohum $seed: son nöbet $last',
          );
        }
      }
    }
  });
}
