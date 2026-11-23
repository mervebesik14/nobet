import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:nobet_listesi/logic/quick_search.dart';
import 'package:nobet_listesi/models/models.dart';

void main() {
  setUpAll(() => initializeDateFormatting('tr_TR'));

  const people = [
    Person(id: 'a', name: 'Ayşe Yılmaz', role: Role.nurse),
    Person(id: 'b', name: 'Banu Kaya', role: Role.nurse),
    Person(id: 't', name: 'Ali Koç', role: Role.radiologyTech),
  ];
  // Aralık 2026: 5–6 hafta sonu.
  const plan = MonthPlan(
    year: 2026,
    month: 12,
    assignments: {
      3: DayAssignment(day: 3, nurseIds: ['a', 'b'], techId: 't'),
      5: DayAssignment(day: 5, nurseIds: ['a'], shift16aIds: ['a']),
      9: DayAssignment(day: 9, nurseIds: ['b']),
    },
    annualLeave: {
      'b': [14, 15, 16],
    },
    unavailableDays: {
      'a': [20],
    },
  );
  List<SearchResult> run(String q) => QuickSearch.run(
    query: q,
    plan: plan,
    people: people,
    today: DateTime(2026, 12, 2),
    weekendDays: const {5, 6, 12, 13},
  );

  test('kişi: nöbetler, izin ve istekler', () {
    final r = run('ayşe');
    expect(r.single.title, 'Ayşe Yılmaz · Hemşire');
    expect(r.single.lines, [
      'Nöbetler (2): 3, 5 (16A)',
      'İstemediği günler: 20',
    ]);
    expect(run('kaya').single.lines, [
      'Nöbetler (2): 3, 9',
      'Yıllık izin: 14–16',
    ]);
  });

  test('gün, yarın, kişi + gün, hafta sonu', () {
    final day = run('3 Aralık').single;
    expect(day.day, 3);
    expect(
      day.lines.first,
      'Nöbetçi: Ayşe Yılmaz (24), Banu Kaya (24), Ali Koç (24)',
    );
    expect(run('yarın').single.day, 3);
    expect(run('Banu 15').single.lines, contains(contains('Yıllık izin')));
    expect(run('ayşe hafta sonu').single.lines, [
      'Hafta sonu nöbetleri (1): 5 (16A)',
    ]);
    expect(run('14').single.lines, [
      'Nöbetçi yazılmamış.',
      'İzinli: Banu Kaya (Yıllık izin)',
    ]);
    expect(run('3 Ocak').single.lines.last, contains('Yalnız seçili ay'));
    expect(run('zzz'), isEmpty);
  });
}
