import 'package:flutter_test/flutter_test.dart';
import 'package:nobet_listesi/logic/block_reason.dart';
import 'package:nobet_listesi/logic/roster_generator.dart';
import 'package:nobet_listesi/logic/roster_validator.dart';
import 'package:nobet_listesi/models/models.dart';

const people = [
  Person(id: 'a', name: 'Ayşe', role: Role.nurse),
  Person(id: 'b', name: 'Banu', role: Role.nurse),
  Person(id: 'c', name: 'Cemile', role: Role.nurse),
  Person(id: 'd', name: 'Derya', role: Role.nurse),
  Person(id: 'm', name: 'Mehmet', role: Role.radiologyTech),
  Person(id: 'z', name: 'Zeynep', role: Role.radiologyTech),
];

/// Kurala uygun 4 günlük bir başlangıç: hemşireler a-b / c-d dönüşümlü,
/// teknikerler m / z dönüşümlü; kalan günler boş.
Map<int, DayAssignment> base() => {
  1: const DayAssignment(day: 1, nurseIds: ['a', 'b'], techId: 'm'),
  2: const DayAssignment(day: 2, nurseIds: ['c', 'd'], techId: 'z'),
  3: const DayAssignment(day: 3, nurseIds: ['a', 'b'], techId: 'm'),
  4: const DayAssignment(day: 4, nurseIds: ['c', 'd'], techId: 'z'),
};

void main() {
  const validator = RosterValidator(RosterSettings());

  List<RuleViolation> check(
    Map<int, DayAssignment> assignments, {
    Map<String, List<int>> unavailable = const {},
    List<Set<String>> tail = const [],
    RosterValidator v = validator,
    int month = 2, // Şubat 2027: 28 gün
  }) => v.validate(
    year: 2027,
    month: month,
    assignments: assignments,
    people: people,
    unavailableDays: unavailable,
    previousMonthTail: tail,
  );

  List<RuleViolation> except(List<RuleViolation> all, ViolationKind kind) =>
      all.where((v) => v.kind != kind).toList();

  test('eksik koltuklar her gün ve rol için raporlanır', () {
    final v = check({
      ...base(),
      5: const DayAssignment(day: 5, nurseIds: ['a']),
    });
    final missing = v.where((x) => x.kind == ViolationKind.missing).toList();
    // 5. gün: 1 hemşire + 1 tekniker; 6-28: 2 hemşire + 1 tekniker satırı.
    expect(missing.where((x) => x.days.single == 5).map((x) => x.message), [
      '5 Şubat: 1 hemşire eksik.',
      '5 Şubat: 1 radyoloji teknikeri eksik.',
    ]);
    expect(missing.length, 2 + 23 * 2);
    expect(
      missing.firstWhere((x) => x.days.single == 6).message,
      '6 Şubat: 2 hemşire eksik.',
    );
  });

  test('tam ve kurala uygun liste: ihlal yok', () {
    // Gerçek bir liste üretip doğrula.
    final r = RosterGenerator(
      year: 2027,
      month: 2,
      people: [
        ...people,
        for (var i = 1; i <= 4; i++)
          Person(id: 'x$i', name: 'Ek $i', role: Role.nurse),
        const Person(id: 'y', name: 'Yusuf', role: Role.radiologyTech),
        const Person(id: 'w', name: 'Veli', role: Role.radiologyTech),
      ],
      attempts: 40,
    ).generate();
    expect(r.isComplete, isTrue);
    expect(
      validator.validate(
        year: 2027,
        month: 2,
        assignments: r.assignments,
        people: people,
      ),
      isEmpty,
    );
  });

  test('istemediği güne atanma', () {
    final v = except(
      check(
        base(),
        unavailable: {
          'm': [3],
        },
      ),
      ViolationKind.missing,
    );
    expect(v.single.kind, ViolationKind.unavailable);
    expect(v.single.personId, 'm');
    expect(v.single.days, [3]);
    expect(v.single.message, 'Mehmet istemediği güne (3 Şubat) atandı.');
  });

  test('kapalı günün nedeni mesajda yazar (izin, rapor, izin öncesi)', () {
    String messageFor(BlockReason reason) => except(
      validator.validate(
        year: 2027,
        month: 2,
        assignments: base(),
        people: people,
        unavailableDays: {
          'm': [3],
        },
        blockReasons: {
          'm': {3: reason},
        },
      ),
      ViolationKind.missing,
    ).single.message;

    expect(
      messageFor(BlockReason.annualLeave),
      'Mehmet yıllık izinli olduğu güne (3 Şubat) atandı.',
    );
    expect(
      messageFor(BlockReason.sickLeave),
      'Mehmet raporlu olduğu güne (3 Şubat) atandı.',
    );
    expect(
      messageFor(BlockReason.beforeAnnualLeave),
      startsWith('Mehmet yıllık izninden hemen önceki güne (3 Şubat) atandı.'),
    );
    expect(
      messageFor(BlockReason.unavailable),
      'Mehmet istemediği güne (3 Şubat) atandı.',
    );
  });

  test('art arda gün', () {
    final a = base();
    a[2] = const DayAssignment(day: 2, nurseIds: ['c', 'd'], techId: 'm');
    final v = except(check(a), ViolationKind.missing);
    final consecutive = v.where((x) => x.kind == ViolationKind.consecutive);
    expect(consecutive.map((x) => x.message), [
      'Mehmet 1 ve 2 Şubat art arda nöbette.',
      'Mehmet 2 ve 3 Şubat art arda nöbette.',
    ]);
    expect(consecutive.first.days, [1, 2]);
  });

  test('art arda gün ayarı kapalıysa raporlanmaz', () {
    final a = base();
    a[2] = const DayAssignment(day: 2, nurseIds: ['c', 'd'], techId: 'm');
    const v = RosterValidator(RosterSettings(forbidConsecutiveDays: false));
    expect(
      check(a, v: v).where((x) => x.kind == ViolationKind.consecutive),
      isEmpty,
    );
  });

  test('gün aşırı zincir: 1-3 olur, 1-3-5 olmaz', () {
    final a = base();
    expect(except(check(a), ViolationKind.missing), isEmpty);

    a[5] = const DayAssignment(day: 5, nurseIds: ['a', 'c'], techId: 'm');
    final chain = check(a).where((x) => x.kind == ViolationKind.chain);
    // Ayşe ve Mehmet 1-3-5.
    expect(chain.map((x) => x.message), [
      'Ayşe 1, 3 ve 5 Şubat gün aşırı nöbette (en fazla 2 olabilir).',
      'Mehmet 1, 3 ve 5 Şubat gün aşırı nöbette (en fazla 2 olabilir).',
    ]);
    expect(chain.first.days, [1, 3, 5]);
  });

  test('zincir sınırı 3 ise 1-3-5 serbest', () {
    final a = base();
    a[5] = const DayAssignment(day: 5, nurseIds: ['a', 'c'], techId: 'm');
    const v = RosterValidator(RosterSettings(maxEveryOtherDayChain: 3));
    expect(check(a, v: v).where((x) => x.kind == ViolationKind.chain), isEmpty);
  });

  test('ay sınırı: önceki ayın son günü ve 1\'i art arda', () {
    final v = check(
      base(),
      tail: [
        {'x'},
        {'a', 'z'},
      ],
    ).where((x) => x.kind == ViolationKind.consecutive);
    expect(v.map((x) => x.message), [
      'Ayşe önceki ayın son günü ve 1 Şubat art arda nöbette.',
    ]);
    expect(v.single.days, [1]);
  });

  test('ay sınırında gün aşırı zincir', () {
    // Önceki ay: -2 ve 0'da Mehmet; bu ay 1 ve 3'te Mehmet: -2, 0 ... ayrı
    // zincir değil; -1 ve 1, 3 → zincir.
    final v = check(
      base(),
      tail: [
        {'m'}, // -1
        <String>{}, // 0
      ],
    ).where((x) => x.kind == ViolationKind.chain);
    expect(v.single.personId, 'm');
    expect(v.single.days, [1, 3]);
    expect(v.single.message, contains('önceki ayın 2. son günü, 1 ve 3 Şubat'));
  });

  test('görevi olmayan koltuk', () {
    final a = base();
    a[1] = const DayAssignment(day: 1, nurseIds: ['a', 'z'], techId: 'm');
    final v = check(a).where((x) => x.kind == ViolationKind.wrongRole);
    expect(
      v.single.message,
      'Zeynep Radyoloji Teknikeri ama 1 Şubat hemşire koltuğunda.',
    );
  });

  test('fazla nöbet sınırı', () {
    // 2 tekniker, 28 gün: ceil(28/2) + 0 = 14. Mehmet'e 15 nöbet ver.
    const v = RosterValidator(
      RosterSettings(
        maxExtraOverAverage: 0,
        forbidConsecutiveDays: false,
        maxEveryOtherDayChain: 99,
      ),
    );
    final a = {
      for (var d = 1; d <= 28; d++)
        d: DayAssignment(
          day: d,
          nurseIds: const ['a', 'b'],
          techId: d <= 15 ? 'm' : 'z',
        ),
    };
    // (Hemşireler a-b de her gün nöbette, onlar da sınırı aşar.)
    final over = check(a, v: v).where(
      (x) => x.kind == ViolationKind.overCap && x.role == Role.radiologyTech,
    );
    expect(
      over.single.message,
      'Mehmet 15 nöbet tutuyor; sınır 14 (grup ortalaması + 0).',
    );
  });

  test('silinmiş kişi adı', () {
    final a = base();
    a[3] = const DayAssignment(day: 3, nurseIds: ['a', 'b'], techId: 'yok');
    final v = check(
      a,
      unavailable: {
        'yok': [3],
      },
    ).where((x) => x.kind == ViolationKind.unavailable);
    expect(v.single.message, startsWith('Silinmiş kişi'));
  });

  test('sorumlu hemşire seçmediği güne yazılırsa uyarı', () {
    const team = [
      ...people,
      Person(id: 's', name: 'Sevgi', role: Role.nurse, isChargeNurse: true),
    ];
    final assignments = {
      ...base(),
      6: const DayAssignment(day: 6, nurseIds: ['s', 'a'], techId: 'm'),
      8: const DayAssignment(day: 8, nurseIds: ['s', 'b'], techId: 'z'),
    };
    final v = validator.validate(
      year: 2027,
      month: 2,
      assignments: assignments,
      people: team,
      requestedShifts: const {
        's': [8],
      },
    );
    final charge = v
        .where((x) => x.kind == ViolationKind.chargeNurseUnrequested)
        .toList();
    expect(charge.length, 1);
    expect(charge.single.days, [6]);
    expect(
      charge.single.message,
      'Sorumlu hemşire Sevgi seçmediği güne (6 Şubat) nöbete yazıldı.',
    );
  });
}
