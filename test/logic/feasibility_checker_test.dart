import 'package:flutter_test/flutter_test.dart';
import 'package:nobet_listesi/logic/feasibility_checker.dart';
import 'package:nobet_listesi/models/models.dart';

List<Person> team(int nurses, int techs) => [
  for (var i = 1; i <= nurses; i++)
    Person(id: 'n$i', name: 'Hemşire $i', role: Role.nurse),
  for (var i = 1; i <= techs; i++)
    Person(id: 't$i', name: 'Tekniker $i', role: Role.radiologyTech),
];

Set<int> allDays(int n) => {for (var d = 1; d <= n; d++) d};

void main() {
  const checker = FeasibilityChecker(RosterSettings());

  FeasibilityReport check(
    List<Person> people, [
    Map<String, List<int>> unavailable = const {},
    FeasibilityChecker c = checker,
  ]) => c.check(
    year: 2026,
    month: 10,
    people: people,
    unavailableDays: unavailable,
  );

  group('maxShifts', () {
    test('kural yoksa uygun gün sayısı', () {
      expect(
        FeasibilityChecker.maxShifts(allDays(31), 31, forbidConsecutive: false),
        31,
      );
      expect(
        FeasibilityChecker.maxShifts({1, 2, 3}, 31, forbidConsecutive: false),
        3,
      );
    });

    test('yalnız art arda gün yasağı: gün aşırı, 31 günde 16', () {
      expect(
        FeasibilityChecker.maxShifts(allDays(31), 31, forbidConsecutive: true),
        16,
      );
    });

    test('art arda yasak + zincir 2: 3-5 olur 3-5-7 olmaz, 31 günde 13', () {
      // Örnek: 1,3,6,8,11,13,16,18,21,23,26,28,31.
      expect(
        FeasibilityChecker.maxShifts(
          allDays(31),
          31,
          forbidConsecutive: true,
          maxChain: 2,
        ),
        13,
      );
      // 3, 5, 7 uygunken en fazla ikisi tutulabilir.
      expect(
        FeasibilityChecker.maxShifts(
          {3, 5, 7},
          31,
          forbidConsecutive: true,
          maxChain: 2,
        ),
        2,
      );
      expect(
        FeasibilityChecker.maxShifts(
          {3, 5, 9, 11},
          31,
          forbidConsecutive: true,
          maxChain: 2,
        ),
        4,
      );
    });

    test('zincir 1: hiç gün aşırı yok', () {
      expect(
        FeasibilityChecker.maxShifts(
          {1, 3, 5, 7},
          31,
          forbidConsecutive: true,
          maxChain: 1,
        ),
        2,
      );
    });

    test('art arda serbest + zincir 2: d, d+2, d+4 yine yasak', () {
      // 1,2,3,4,5: 1-3-5 zinciri yasak, en fazla 4 (ör. 1,2,4,5).
      expect(
        FeasibilityChecker.maxShifts(
          {1, 2, 3, 4, 5},
          31,
          forbidConsecutive: false,
          maxChain: 2,
        ),
        4,
      );
    });
  });

  test('yeterli ekipte sorun yok', () {
    final report = check(team(7, 4));
    expect(report.isFeasible, isTrue);
    expect(report.issues, isEmpty);
  });

  test('pasif kişiler sayılmaz, rolde kimse yoksa uyarı', () {
    final people = [
      ...team(7, 0),
      const Person(
        id: 'x',
        name: 'Pasif Tekniker',
        role: Role.radiologyTech,
        isActive: false,
      ),
    ];
    final issues = check(people).issues;
    expect(issues, hasLength(1));
    expect(issues.single.kind, FeasibilityIssueKind.noPeople);
    expect(issues.single.message, 'Hiç aktif radyoloji teknikeri yok.');
  });

  test('bir günde uygun tekniker yoksa o gün raporlanır', () {
    final issues = check(team(7, 4), {
      't1': [14],
      't2': [14],
      't3': [14],
      't4': [14, 20],
    }).issues;
    final day = issues.where((i) => i.kind == FeasibilityIssueKind.dayShortage);
    expect(day.single.day, 14);
    expect(day.single.role, Role.radiologyTech);
    expect(day.single.message, '14 Ekim: uygun radyoloji teknikeri yok.');
  });

  test('bir günde 1 hemşire uygunsa sayı belirtilir', () {
    final unavailable = {
      for (var i = 2; i <= 7; i++) 'n$i': [5],
    };
    final day = check(
      team(7, 4),
      unavailable,
    ).issues.where((i) => i.kind == FeasibilityIssueKind.dayShortage).single;
    expect(day.message, '5 Ekim: uygun hemşire sayısı 1, gereken 2.');
  });

  test('ardışık iki güne yetecek farklı kişi yoksa raporlanır', () {
    // 5 hemşire; 10 ve 11 Ekim'de yalnız n1-n2 uygun. Her gün tek başına
    // yeterli ama iki güne 4 farklı hemşire gerekir.
    final issues = check(team(5, 4), {
      'n3': [10, 11],
      'n4': [10, 11],
      'n5': [10, 11],
    }).issues;
    final pair = issues.where(
      (i) => i.kind == FeasibilityIssueKind.pairShortage,
    );
    expect(pair.single.day, 10);
    expect(pair.single.message, contains('10 Ekim – 11 Ekim'));
    expect(pair.single.message, contains('4 farklı hemşire gerekiyor'));
  });

  test('art arda gün serbestse ardışık gün kontrolü yapılmaz', () {
    const c = FeasibilityChecker(RosterSettings(forbidConsecutiveDays: false));
    final issues = check(team(5, 4), {
      'n3': [10, 11],
      'n4': [10, 11],
      'n5': [10, 11],
    }, c).issues;
    expect(
      issues.where((i) => i.kind == FeasibilityIssueKind.pairShortage),
      isEmpty,
    );
  });

  group('kapasite', () {
    test('2 tekniker 31 gün: kural yüzünden yetmez, kural adı söylenir', () {
      // Her biri en fazla 13 → 26 < 31.
      final issues = check(team(7, 2)).issues;
      final cap = issues
          .where((i) => i.kind == FeasibilityIssueKind.capacity)
          .single;
      expect(cap.role, Role.radiologyTech);
      expect(cap.message, contains('31 nöbet gerekiyor (2 kişi)'));
      expect(cap.message, contains('gün aşırı zincir sınırı'));
      expect(cap.message, contains('en fazla 26 nöbet'));
    });

    test('3 tekniker 31 gün yeterli', () {
      expect(
        check(
          team(7, 3),
        ).issues.where((i) => i.kind == FeasibilityIssueKind.capacity),
        isEmpty,
      );
    });

    test('1 tekniker: art arda gün yasağı da yetmez, iki kural listelenir', () {
      final cap = check(
        team(7, 1),
      ).issues.where((i) => i.kind == FeasibilityIssueKind.capacity).single;
      expect(cap.message, contains('art arda gün yasağı ve gün aşırı'));
    });

    test('istenmeyen günler yüzünden yetmezse bu söylenir', () {
      // 3 tekniker, her biri ayın 21 gününü istemiyor: 3 × 10 = 30 < 31.
      final issues = check(team(7, 3), {
        't1': [for (var d = 1; d <= 21; d++) d],
        't2': [for (var d = 6; d <= 26; d++) d],
        't3': [for (var d = 11; d <= 31; d++) d],
      }).issues;
      final cap = issues
          .where((i) => i.kind == FeasibilityIssueKind.capacity)
          .single;
      expect(cap.message, contains('istenmeyen günler'));
    });

    test('fazla nöbet sınırı yetersizliğe yol açarsa söylenir', () {
      // t3 yalnız 1-15 Ekim uygun (en fazla 6 nöbet). Sınırsız:
      // 13 + 13 + 6 = 32 ≥ 31. Sınır ceil(31/3) + 0 = 11: 11 + 11 + 6 = 28.
      const c = FeasibilityChecker(RosterSettings(maxExtraOverAverage: 0));
      final issues = check(team(7, 3), {
        't3': [
          for (var d = 1; d <= 31; d++)
            if (d > 15) d,
        ],
      }, c).issues;
      final cap = issues
          .where((i) => i.kind == FeasibilityIssueKind.capacity)
          .single;
      expect(cap.message, contains('fazla nöbet sınırı'));
    });
  });

  group('sorumlu hemşire', () {
    final people = [
      ...team(7, 4),
      const Person(
        id: 'c',
        name: 'Sorumlu',
        role: Role.nurse,
        isChargeNurse: true,
      ),
    ];
    // 14 Ekim'de n2–n7 istemiyor: n1 ve sorumlu hemşire kalır.
    final unavailable = {
      for (var i = 2; i <= 7; i++) 'n$i': [14],
    };

    test('seçmediği gün uygun sayılmaz', () {
      final r = check(people, unavailable);
      expect(r.issues.map((i) => i.message), [
        '14 Ekim: uygun hemşire sayısı 1, gereken 2.',
      ]);
    });

    test('seçtiği gün uygun sayılır', () {
      final r = checker.check(
        year: 2026,
        month: 10,
        people: people,
        unavailableDays: unavailable,
        requestedShifts: const {
          'c': [14],
        },
      );
      expect(r.isFeasible, isTrue);
    });
  });
}
