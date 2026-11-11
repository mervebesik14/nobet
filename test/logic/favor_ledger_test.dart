import 'package:flutter_test/flutter_test.dart';
import 'package:nobet_listesi/logic/favor_ledger.dart';
import 'package:nobet_listesi/logic/swap_log.dart';

void main() {
  final at = DateTime(2026, 10, 1);
  SwapEntry change(int day, String? from, String? to) =>
      SwapEntry.change(at: at, day: day, from: from, to: to);
  const roles = {'a': 'n', 'b': 'n', 'c': 'n', 't': 't'};
  Object? roleOf(String id) => roles[id];
  String name(String id) =>
      {'a': 'Ayşe', 'b': 'Banu', 'c': 'Cemile', 't': 'Ali'}[id] ?? id;

  test('yerine geçen alacaklı; geri ödenen borç kapanır', () {
    final ledger = FavorLedger.build({
      9: [change(5, 'a', 'b')],
      10: [
        change(3, 'a', 'b'),
        change(8, 'b', 'a'), // Ayşe bir tanesini ödedi
        change(12, 'c', 'a'),
      ],
    }, roleOf: roleOf);
    expect(ledger.owes('a', 'b'), 1);
    expect(ledger.owes('b', 'a'), 0);
    expect(ledger.owes('c', 'a'), 1);
    expect(ledger.debtorsOf('a'), {'c': 1});
    expect(ledger.debts.first.favors.length, 3);
    expect(ledger.favors.length, 4);
  });

  test('takas, ekleme/çıkarma ve farklı rol sayılmaz', () {
    final ledger = FavorLedger.build({
      10: [
        SwapEntry.swap(at: at, a: 'a', dayA: 3, b: 'b', dayB: 5),
        change(4, 'a', null),
        change(6, null, 'b'),
        change(7, 'a', 't'),
        change(9, 'a', 'x'), // silinmiş kişi
      ],
    }, roleOf: roleOf);
    expect(ledger.debts, isEmpty);
    expect(ledger.text(2026, name), '2026 iyilik defteri\nAçık borç yok.');
  });

  test('metin', () {
    final ledger = FavorLedger.build({
      10: [change(3, 'a', 'b'), change(5, 'a', 'b')],
    }, roleOf: roleOf);
    expect(
      ledger.text(2026, name),
      '2026 iyilik defteri\n'
      '• Ayşe → Banu: 2 nöbet\n'
      '   3 Ekim: Banu, Ayşe yerine\n'
      '   5 Ekim: Banu, Ayşe yerine',
    );
  });
}
