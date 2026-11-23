import 'package:flutter_test/flutter_test.dart';
import 'package:nobet_listesi/logic/team_rules.dart';
import 'package:nobet_listesi/models/models.dart';

void main() {
  const people = [
    Person(
      id: 'a',
      name: 'Ayşe',
      role: Role.nurse,
      seniority: Seniority.senior,
    ),
    Person(id: 'b', name: 'Banu', role: Role.nurse),
    Person(
      id: 'e',
      name: 'Elif',
      role: Role.nurse,
      seniority: Seniority.novice,
    ),
    Person(id: 'f', name: 'Fatma', role: Role.nurse),
  ];
  const rules = [
    PairRule(a: 'b', b: 'f'),
    PairRule(a: 'a', b: 'e', together: true),
  ];

  test('ayrı, birlikte ve kıdemli', () {
    final t = TeamRules(people, rules);
    expect(t.isApart('f', 'b'), isTrue);
    expect(t.apartClashes(['b', 'f']), [('b', 'f')]);
    expect(t.apartClashes(['a', 'b']), isEmpty);
    expect(t.togetherHits(['e', 'a']), 1);
    expect(t.unsupervised(['e', 'b']), ['e']);
    expect(t.unsupervised(['e', 'a']), isEmpty);
    expect(t.isEmpty, isFalse);
    expect(TeamRules(const [], const []).isEmpty, isTrue);
  });

  test('düz cümleler', () {
    expect(TeamRules.describe(rules, people), [
      'Banu ile Fatma aynı gün nöbet tutmaz.',
      'Ayşe ile Elif mümkünse aynı gün.',
      'Elif: yeni başlayan; yanında en az bir kıdemli olur.',
    ]);
  });

  test('kişi ve ayar JSON', () {
    final p = people[2];
    expect(Person.fromJson(p.toJson()), p);
    expect(people[1].toJson().containsKey('seniority'), isFalse);
    const s = RosterSettings(pairRules: rules);
    expect(RosterSettings.fromJson(s.toJson()), s);
  });
}
