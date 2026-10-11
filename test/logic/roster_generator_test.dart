import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:nobet_listesi/data/turkish_holidays.dart';
import 'package:nobet_listesi/logic/roster_generator.dart';
import 'package:nobet_listesi/models/models.dart';

List<Person> team(int nurses, int techs) => [
  for (var i = 1; i <= nurses; i++)
    Person(id: 'n$i', name: 'Hemşire $i', role: Role.nurse),
  for (var i = 1; i <= techs; i++)
    Person(id: 't$i', name: 'Tekniker $i', role: Role.radiologyTech),
];

/// Kişi → nöbet tuttuğu günler.
Map<String, Set<int>> workedDays(RosterResult r) {
  final result = <String, Set<int>>{};
  for (final a in r.assignments.values) {
    for (final id in a.personIds) {
      (result[id] ??= {}).add(a.day);
    }
  }
  return result;
}

int spread(Iterable<int> values) =>
    values.reduce((a, b) => a > b ? a : b) -
    values.reduce((a, b) => a < b ? a : b);

/// Sert kuralların hepsini doğrular.
void expectHardRules(
  RosterResult r,
  List<Person> people,
  Map<String, List<int>> unavailable,
  RosterSettings settings, {
  int days = 31,
}) {
  expect(r.isComplete, isTrue, reason: r.issues.join('\n'));
  final roles = {for (final p in people) p.id: p.role};
  for (var d = 1; d <= days; d++) {
    final a = r.assignments[d]!;
    expect(a.nurseIds.length, settings.nursesPerDay, reason: 'gün $d');
    expect(a.nurseIds.toSet().length, a.nurseIds.length, reason: 'gün $d');
    expect(a.techId, isNotNull, reason: 'gün $d');
    for (final id in a.nurseIds) {
      expect(roles[id], Role.nurse);
    }
    expect(roles[a.techId], Role.radiologyTech);
    for (final id in a.personIds) {
      expect(
        unavailable[id] ?? const [],
        isNot(contains(d)),
        reason: '$id istemediği $d. günde',
      );
    }
  }
  for (final MapEntry(key: id, value: worked) in workedDays(r).entries) {
    for (final d in worked) {
      if (settings.forbidConsecutiveDays) {
        expect(worked.contains(d + 1), isFalse, reason: '$id $d ve ${d + 1}');
      }
      final chain = [
        for (var k = 0; k <= settings.maxEveryOtherDayChain; k++) d + 2 * k,
      ];
      expect(
        chain.every(worked.contains),
        isFalse,
        reason: '$id gün aşırı zincir $chain',
      );
    }
  }
}

/// Rol grubu içinde toplam, hafta sonu ve gün aşırı çift farkları.
({int total, int weekend, int pairs}) spreads(
  RosterResult r,
  List<Person> people,
  Role role,
  Set<int> weekendDays,
) {
  final worked = workedDays(r);
  final ids = [
    for (final p in people)
      if (p.role == role) p.id,
  ];
  final sets = [for (final id in ids) worked[id] ?? <int>{}];
  return (
    total: spread(sets.map((s) => s.length)),
    weekend: spread(sets.map((s) => s.where(weekendDays.contains).length)),
    pairs: spread(sets.map(RosterGenerator.everyOtherDayPairs)),
  );
}

void main() {
  final holidays = TurkishHolidays.forYear(2026);
  const settings = RosterSettings();

  RosterGenerator generator({
    List<Person>? people,
    Map<String, List<int>> unavailable = const {},
    RosterSettings s = settings,
    int seed = 1,
    List<Set<String>> tail = const [],
    int attempts = 150,
    int month = 10,
  }) => RosterGenerator(
    year: 2026,
    month: month,
    people: people ?? team(7, 4),
    unavailableDays: unavailable,
    holidays: holidays,
    settings: s,
    seed: seed,
    previousMonthTail: tail,
    attempts: attempts,
  );

  group('weekendDays', () {
    test('Cmt/Paz ve ayara göre tam gün tatil; arife hafta içi', () {
      final w = RosterGenerator.weekendDays(2026, 10, holidays, settings);
      expect(w, {3, 4, 10, 11, 17, 18, 24, 25, 29, 31});
      expect(w.contains(28), isFalse);

      final noHoliday = RosterGenerator.weekendDays(
        2026,
        10,
        holidays,
        const RosterSettings(holidayCountsAsWeekend: false),
      );
      expect(noHoliday.contains(29), isFalse);
      expect(noHoliday.length, 9);
    });
  });

  test('everyOtherDayPairs', () {
    expect(RosterGenerator.everyOtherDayPairs({3, 5, 10, 12, 20}), 2);
    expect(RosterGenerator.everyOtherDayPairs({1, 4, 7}), 0);
  });

  group('31 gün, 7 hemşire, 4 tekniker', () {
    final people = team(7, 4);
    const unavailable = {
      'n1': [1, 2, 3],
      'n2': [10, 11],
      'n3': [20],
      'n5': [29, 30, 31],
      't1': [5, 6],
      't3': [17, 18],
    };
    final weekend = RosterGenerator.weekendDays(2026, 10, holidays, settings);

    for (final seed in [1, 2, 3]) {
      test('tohum $seed: sert kurallar ve adalet (fark ≤ 1)', () {
        final r = generator(unavailable: unavailable, seed: seed).generate();
        expectHardRules(r, people, unavailable, settings);

        for (final role in Role.values) {
          final s = spreads(r, people, role, weekend);
          expect(s.total, lessThanOrEqualTo(1), reason: '$role toplam');
          expect(s.weekend, lessThanOrEqualTo(1), reason: '$role hafta sonu');
          expect(s.pairs, lessThanOrEqualTo(1), reason: '$role gün aşırı');
        }
        expect(r.score, lessThan(RosterGenerator.emptySlotPenalty));
      });
    }

    test('istenmeyen gün yokken de geçerli ve adil', () {
      final r = generator(seed: 7).generate();
      expectHardRules(r, people, const {}, settings);
      for (final role in Role.values) {
        expect(spreads(r, people, role, weekend).total, lessThanOrEqualTo(1));
      }
    });
  });

  test('aynı tohum aynı sonucu verir, farklı tohum farklı liste', () {
    final a = generator(seed: 42).generate();
    final b = generator(seed: 42).generate();
    final c = generator(seed: 43).generate();
    expect(a.assignments, b.assignments);
    expect(a.score, b.score);
    expect(a.seed, 42);
    expect(c.assignments, isNot(a.assignments));
  });

  test('pasif kişilere nöbet verilmez', () {
    final people = [
      ...team(7, 4),
      const Person(id: 'p', name: 'Pasif', role: Role.nurse, isActive: false),
    ];
    final r = generator(people: people).generate();
    expect(workedDays(r).containsKey('p'), isFalse);
  });

  group('imkânsız senaryo', () {
    test('bir günde uygun tekniker yoksa o gün açıklamalı rapor', () {
      final r = generator(
        unavailable: const {
          't1': [18],
          't2': [18],
          't3': [18],
          't4': [18],
        },
      ).generate();

      expect(r.isComplete, isFalse);
      final issue = r.issues.single;
      expect(issue.day, 18);
      expect(issue.role, Role.radiologyTech);
      expect(issue.missing, 1);
      expect(
        issue.message,
        '18 Ekim: 1 radyoloji teknikeri eksik. Tekniker 1 istemiyor; '
        'Tekniker 2 istemiyor; Tekniker 3 istemiyor; Tekniker 4 istemiyor.',
      );
      // Diğer günler yine dolu ve kurallara uygun.
      expect(r.assignments[18]!.techId, isNull);
      expect(r.assignments[18]!.nurseIds.length, 2);
      expect(r.assignments[17]!.techId, isNotNull);
    });

    test('2 tekniker 31 gün: eksik günler kural nedeniyle raporlanır', () {
      final r = generator(people: team(7, 2), attempts: 60).generate();
      expect(r.isComplete, isFalse);
      expect(r.issues.every((i) => i.role == Role.radiologyTech), isTrue);
      // Art arda yasak + zincir 2 ile bir kişi ardışık 5 günde en fazla
      // 2 nöbet tutar; 2 tekniker 5 günün en fazla 4'ünü kapatır. 31 günde
      // en fazla 6 × 4 + 1 = 25 gün dolar: en iyi sonuç 6 boş gün.
      expect(r.issues.length, 6);
      expect(
        r.issues.first.message,
        anyOf(contains('art arda gün'), contains('gün aşırı zincir')),
      );
    });

    test('rolde hiç kimse yoksa her gün raporlanır', () {
      final r = generator(people: team(7, 0), attempts: 10).generate();
      expect(r.issues.length, 31);
      expect(r.issues.first.message, contains('Hiç aktif radyoloji teknikeri'));
    });
  });

  group('ayarlar', () {
    test('art arda gün serbestse 2 teknikerle ay dolabilir', () {
      const s = RosterSettings(forbidConsecutiveDays: false);
      final people = team(7, 2);
      final r = generator(people: people, s: s).generate();
      expectHardRules(r, people, const {}, s);
    });

    test('fazla nöbet sınırı: kimse ceil(ortalama) + N üstüne çıkmaz', () {
      const s = RosterSettings(maxExtraOverAverage: 0);
      final people = team(7, 4);
      final r = generator(people: people, s: s).generate();
      expectHardRules(r, people, const {}, s);
      final worked = workedDays(r);
      for (final p in people) {
        final limit = p.role == Role.nurse ? 9 : 8; // ceil(62/7), ceil(31/4)
        expect(worked[p.id]!.length, lessThanOrEqualTo(limit));
      }
    });

    test('zincir 3 ise 3-5-7 olabilir, 3-5-7-9 olmaz', () {
      const s = RosterSettings(maxEveryOtherDayChain: 3);
      final people = team(7, 4);
      final r = generator(people: people, s: s).generate();
      expectHardRules(r, people, const {}, s);
    });
  });

  group('önceki ay devri', () {
    test('önceki ayın son günü nöbetçisi 1\'inde nöbet tutmaz', () {
      final tail = [
        <String>{'n1', 'n2', 't1'},
      ];
      for (final seed in [1, 2, 3, 4]) {
        final r = generator(tail: tail, seed: seed, attempts: 40).generate();
        expect(r.assignments[1]!.personIds, isNot(contains('n1')));
        expect(r.assignments[1]!.personIds, isNot(contains('n2')));
        expect(r.assignments[1]!.personIds, isNot(contains('t1')));
      }
    });

    test(
      'ay sınırında gün aşırı zincir: önceki ay -2 ve son gün → 2\'si yok',
      () {
        // Son 3 gün: [ -2: t1 ], [ -1: — ], [ 0: t1 ].
        final tail = [
          <String>{'t1'},
          <String>{},
          <String>{'t1'},
        ];
        for (final seed in [1, 2, 3, 4]) {
          final r = generator(tail: tail, seed: seed, attempts: 40).generate();
          expect(r.assignments[1]!.techId, isNot('t1'));
          expect(r.assignments[2]!.techId, isNot('t1'));
        }
      },
    );
  });

  test('Şubat (28 gün) ve az kişi: 5 hemşire, 3 tekniker', () {
    final people = team(5, 3);
    final r = generator(people: people, month: 2).generate();
    expectHardRules(r, people, const {}, settings, days: 28);
    expect(r.assignments.length, 28);
  });

  test('400 deneme makul sürede biter', () {
    final sw = Stopwatch()..start();
    generator(attempts: 400).generate();
    expect(sw.elapsed, lessThan(const Duration(seconds: 10)));
  });

  test('ayrı isolate içinde çalışır ve aynı sonucu verir', () async {
    final g = generator(seed: 5, attempts: 30);
    final inIsolate = await Isolate.run(g.generate);
    expect(inIsolate.assignments, g.generate().assignments);
  });
}
