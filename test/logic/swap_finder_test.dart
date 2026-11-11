import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:nobet_listesi/logic/roster_validator.dart';
import 'package:nobet_listesi/logic/swap_finder.dart';
import 'package:nobet_listesi/models/models.dart';

void main() {
  setUpAll(() => initializeDateFormatting('tr_TR'));

  const people = [
    Person(id: 'a', name: 'Ayşe', role: Role.nurse),
    Person(id: 'b', name: 'Banu', role: Role.nurse),
    Person(id: 'c', name: 'Cemile', role: Role.nurse),
    Person(id: 't', name: 'Tarık', role: Role.radiologyTech),
  ];
  // Kasım 2026, günde 1 hemşire. Ayşe 10'da; Banu 11 ve 20'de; Cemile 5'te.
  final plan = MonthPlan(
    year: 2026,
    month: 11,
    assignments: {
      5: const DayAssignment(day: 5, nurseIds: ['c']),
      10: const DayAssignment(day: 10, nurseIds: ['a'], techId: 't'),
      11: const DayAssignment(day: 11, nurseIds: ['b']),
      20: const DayAssignment(day: 20, nurseIds: ['b']),
    },
  );

  List<RuleViolation> validate(Map<int, DayAssignment> a) =>
      RosterValidator(const RosterSettings(nursesPerDay: 1))
          .validate(year: 2026, month: 11, assignments: a, people: people)
          .where((v) => v.kind != ViolationKind.missing)
          .toList();

  test('yeni ihlal doğurmayan takaslar, yakın tarih önce', () {
    final options = SwapFinder.find(
      plan: plan,
      people: people,
      personId: 'a',
      day: 10,
      nursesPerDay: 1,
      validate: validate,
    );
    final pairs = [for (final o in options) '${o.otherId}${o.otherDay}'];
    // Banu 11 ile: Banu 10 + 20, Ayşe 11 (art arda yok). Cemile 5 de uygun.
    // Banu 20 ile olmaz: Banu 10 ve 11'de art arda kalırdı.
    expect(pairs, ['b11', 'c5']);
    expect(pairs.first, 'b11');
    // Teknikerler önerilmez.
    expect(options.every((o) => o.otherId != 't'), isTrue);
    final swapped = options.first.after;
    expect(swapped[10]!.nurseIds, ['b']);
    expect(swapped[11]!.nurseIds, ['a']);

    // Ayşe'ye iyilik borcu olan önce gelir.
    final owed = SwapFinder.find(
      plan: plan,
      people: people,
      personId: 'a',
      day: 10,
      nursesPerDay: 1,
      validate: validate,
      debts: const {'c': 1},
    );
    expect([for (final o in owed) '${o.otherId}${o.otherDay}'], ['c5', 'b11']);
  });

  test('art arda doğuracak takas önerilmez', () {
    // Banu 11'de; Ayşe 12'ye de yazılırsa 11'i alınca art arda olur.
    final p = plan.copyWith(
      assignments: {
        ...plan.assignments,
        12: const DayAssignment(day: 12, nurseIds: ['a']),
      },
    );
    final options = SwapFinder.find(
      plan: p,
      people: people,
      personId: 'a',
      day: 10,
      nursesPerDay: 1,
      validate: validate,
    );
    expect(options.any((o) => o.otherId == 'b' && o.otherDay == 11), isFalse);
  });

  test('teklif mesajı', () {
    expect(
      SwapFinder.offer(
        plan: plan,
        personName: 'Ayşe',
        day: 10,
        otherName: 'Banu',
        otherDay: 11,
      ),
      'Merhaba Banu, Ayşe 10 Kasım Salı nöbetini seninle değiştirmek '
      'istiyor: sen 10 Kasım Salı, Ayşe 11 Kasım Çarşamba nöbetini '
      'tutacak. Uygun musun?',
    );
  });
}
