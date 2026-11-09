import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:nobet_listesi/logic/block_reason.dart';
import 'package:nobet_listesi/logic/shift_explainer.dart';
import 'package:nobet_listesi/models/models.dart';

void main() {
  setUpAll(() => initializeDateFormatting('tr_TR'));

  const people = [
    Person(id: 'a', name: 'Ayşe', role: Role.nurse),
    Person(id: 'b', name: 'Banu', role: Role.nurse),
    Person(id: 'c', name: 'Cemile', role: Role.nurse),
    Person(id: 'd', name: 'Derya', role: Role.nurse),
    Person(id: 'e', name: 'Elif', role: Role.nurse),
    Person(id: 'f', name: 'Fatma', role: Role.nurse),
    Person(id: 's', name: 'Sorumlu', role: Role.nurse, isChargeNurse: true),
    Person(id: 't', name: 'Tarık', role: Role.radiologyTech),
  ];
  // Kasım 2026: 10 Salı. Ayşe 10'da; Banu 9'da (art arda), Cemile 6-8'de
  // (8 + 10 + ... zincir değil), Derya'nın 3 nöbeti, Elif istemedi.
  MonthPlan plan() => MonthPlan(
    year: 2026,
    month: 11,
    assignments: {
      1: const DayAssignment(day: 1, nurseIds: ['d', 'f']),
      3: const DayAssignment(day: 3, nurseIds: ['d']),
      5: const DayAssignment(day: 5, nurseIds: ['d', 'c']),
      9: const DayAssignment(day: 9, nurseIds: ['b']),
      10: const DayAssignment(day: 10, nurseIds: ['a', 'f'], techId: 't'),
      14: const DayAssignment(day: 14, nurseIds: ['c', 'e']),
    },
    unavailableDays: const {
      'e': [10],
    },
  );

  test('kişi bilgileri ve diğerlerinin nedenleri', () {
    final x = ShiftExplainer.explain(
      plan: plan(),
      people: people,
      personId: 'a',
      day: 10,
      settings: const RosterSettings(),
      blockReasons: const {
        'e': {10: BlockReason.unavailable},
      },
    );
    expect(x.title, 'Ayşe · 10 Kasım Salı');
    expect(x.facts.first, 'Bu ay 1 nöbeti var; hemşire ortalaması 1,7.');
    expect(x.warnings, isEmpty);
    final reasons = {for (final o in x.others) o.personId: o.reason};
    // Aynı gün nöbette olan Fatma ve tekniker listede yok.
    expect(reasons.keys, isNot(contains('f')));
    expect(reasons.keys, isNot(contains('t')));
    expect(reasons['e'], 'istemediği gün');
    expect(reasons['b'], startsWith('bir gün önce'));
    expect(reasons['s'], startsWith('sorumlu hemşire'));
    expect(reasons['d'], startsWith('bu ay zaten 3 nöbeti var'));
    expect(reasons['c'], startsWith('bu ay zaten 2 nöbeti var'));
    // Kesin engeller önce.
    expect(x.others.first.reason, isNot(startsWith('bu ay zaten')));
    expect(x.others.last.reason, startsWith('bu ay zaten'));
  });

  test('gün aşırı zincir ve kişinin kendi uyarısı', () {
    final p = plan().copyWith(
      assignments: {
        ...plan().assignments,
        // Derya 1-3-5'te: 7'ye yazılsa zincir 4 olurdu.
        7: const DayAssignment(day: 7, nurseIds: ['a', 'b']),
        6: const DayAssignment(day: 6, nurseIds: ['a']),
      },
    );
    final x = ShiftExplainer.explain(
      plan: p,
      people: people,
      personId: 'a',
      day: 7,
      settings: const RosterSettings(),
      blockReasons: const {
        'a': {7: BlockReason.unavailable},
      },
    );
    final reasons = {for (final o in x.others) o.personId: o.reason};
    expect(reasons['d'], contains('gün aşırı zinciri 4'));
    expect(
      x.warnings,
      contains('Dikkat: istemediği gün (elle yazılmış olabilir).'),
    );
    expect(x.warnings, contains('Dikkat: bir gün önce de nöbette (art arda).'));
  });
}
