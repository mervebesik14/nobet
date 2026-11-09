import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:nobet_listesi/logic/request_fulfillment.dart';
import 'package:nobet_listesi/models/models.dart';

void main() {
  setUpAll(() => initializeDateFormatting('tr_TR'));

  const people = [
    Person(id: 'a', name: 'Ayşe', role: Role.nurse),
    Person(id: 'b', name: 'Banu', role: Role.nurse),
    Person(id: 'c', name: 'Cemile', role: Role.nurse),
    Person(id: 's', name: 'Sorumlu', role: Role.nurse, isChargeNurse: true),
  ];

  MonthPlan plan(
    int month,
    Map<String, List<int>> shifts, {
    Set<String> overtime = const {},
    Map<String, List<int>> unavailable = const {},
    Map<String, List<int>> annual = const {},
    Map<String, List<int>> requested = const {},
  }) {
    final byDay = <int, List<String>>{};
    for (final e in shifts.entries) {
      for (final d in e.value) {
        (byDay[d] ??= []).add(e.key);
      }
    }
    return MonthPlan(
      year: 2026,
      month: month,
      assignments: {
        for (final e in byDay.entries)
          e.key: DayAssignment(day: e.key, nurseIds: e.value),
      },
      overtimeRequests: overtime,
      unavailableDays: unavailable,
      annualLeave: annual,
      requestedShifts: requested,
    );
  }

  test('ay: istemediği gün, izin, seçtiği gün, fazla mesai', () {
    final r = RequestFulfillment.forMonth(
      plan(
        9,
        {
          'a': [1, 4, 7],
          'b': [2, 5],
          'c': [3, 6],
          's': [10],
        },
        overtime: {'a', 'b'},
        unavailable: {
          'a': [2, 4],
        },
        annual: {
          'c': [6, 7],
        },
        requested: {
          's': [10, 12],
        },
      ),
      people,
    );
    // Ayşe: 2 istemedi (karşılandı), 4 istemedi ama yazıldı; fazla mesai
    // 3 > Cemile'nin 2'si.
    expect([for (final i in r['a']!) i.met], [true, false, true]);
    expect(r['a']![1].detail, '4 Eylül istemedi');
    // Banu: 2 nöbet, ortalama 2 → karşılanmadı.
    expect(r['b']!.single.met, isFalse);
    expect(r['b']!.single.detail, '2 nöbet (istemeyenlerin ortalaması 2)');
    // Cemile izinde 6'da nöbet.
    expect(r['c']!.single.met, isFalse);
    expect(r['c']!.single.detail, 'Yıllık izin sırasında nöbet: 6 Eylül');
    // Sorumlu 10 karşılandı, 12 değil.
    expect([for (final i in r['s']!) i.met], [true, false]);
  });

  test('yıl: oran, döküm ve fazla mesai önceliği', () {
    final plans = [
      plan(
        9,
        {
          'a': [1, 4],
          'b': [2, 5],
          'c': [3, 6],
        },
        overtime: {'a'},
      ),
      plan(
        10,
        {
          'a': [1, 4, 7],
          'b': [2, 5],
          'c': [3, 6],
        },
        overtime: {'b'},
        unavailable: {
          'a': [9],
        },
      ),
    ];
    final year = RequestFulfillment.forYear(
      year: 2026,
      plans: plans,
      people: people,
    );
    final a = year.firstWhere((r) => r.personId == 'a');
    expect(a.total, 2);
    expect(a.met, 1);
    expect(a.percent, 50);
    expect(a.breakdown, 'İstemediği gün 1/1 · Fazla mesai 0/1');
    // Kasım için: Ayşe'nin Eylül isteği karşılanmadı; Banu'nun Ekim isteği
    // de (2 nöbet, ortalama 2,5).
    expect(
      RequestFulfillment.overtimePriority(
        year: 2026,
        month: 11,
        plans: plans,
        people: people,
      ),
      {'a', 'b'},
    );
    expect(
      RequestFulfillment.overtimePriority(
        year: 2026,
        month: 10,
        plans: plans,
        people: people,
      ),
      {'a'},
    );
  });
}
