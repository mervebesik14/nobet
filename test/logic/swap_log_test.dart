import 'package:flutter_test/flutter_test.dart';
import 'package:nobet_listesi/logic/swap_log.dart';
import 'package:nobet_listesi/models/models.dart';

void main() {
  DayAssignment a(int d, List<String> nurses) =>
      DayAssignment(day: d, nurseIds: nurses);
  const names = {'a': 'Ayşe', 'b': 'Banu', 'c': 'Cemile', 'd': 'Derya'};
  String name(String id) => names[id]!;

  final generated = {
    3: a(3, ['a', 'c']),
    4: a(4, ['b', 'd']),
    5: a(5, ['c', 'd']),
  };

  test('takas, yerine yazma, ekleme; oluşturma kaydı sayılmaz', () {
    final swapped = {
      ...generated,
      3: a(3, ['b', 'c']),
      4: a(4, ['a', 'd']),
    };
    final replaced = {
      ...swapped,
      5: a(5, ['c', 'a']),
    };
    final edits = [
      RosterEdit(at: DateTime(2026, 10, 1), title: 'Liste oluşturuldu'),
      RosterEdit(
        at: DateTime(2026, 10, 2),
        title: 'Elle değişiklik',
        before: generated,
      ),
      RosterEdit(
        at: DateTime(2026, 10, 3),
        title: 'Elle değişiklik',
        before: swapped,
      ),
    ];
    final log = SwapLog.build(edits, replaced);
    expect(log.map((e) => e.describe(10, name)), [
      'Ayşe 3 Ekim ↔ Banu 4 Ekim',
      '5 Ekim: Derya yerine Ayşe',
    ]);
    expect(log.first.isSwap, isTrue);
    expect(log.first.at, DateTime(2026, 10, 2));
  });

  test('yalnız çıkarma ve ekleme; metin', () {
    final log = SwapLog.build(
      [
        RosterEdit(
          at: DateTime(2026, 10, 2),
          title: 'Elle değişiklik',
          before: generated,
        ),
      ],
      {
        ...generated,
        3: a(3, ['a']),
        6: a(6, ['b']),
      },
    );
    expect(log.map((e) => e.describe(10, name)), [
      '3 Ekim: Cemile çıkarıldı',
      '6 Ekim: Banu eklendi',
    ]);
    expect(
      SwapLog.text(year: 2026, month: 10, entries: log, name: name),
      'Ekim 2026 takas defteri\n• 3 Ekim: Cemile çıkarıldı\n'
      '• 6 Ekim: Banu eklendi',
    );
    expect(
      SwapLog.text(year: 2026, month: 10, entries: const [], name: name),
      contains('elle değişiklik yok'),
    );
  });
}
