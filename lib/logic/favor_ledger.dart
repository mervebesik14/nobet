import 'swap_log.dart';
import 'turkish_dates.dart';

/// Bir iyilik: [month] ayının [day] gününde [helper], [helped] yerine nöbet
/// tuttu.
typedef Favor = ({int month, int day, String helped, String helper});

/// İki kişi arasındaki net borç: [debtor], [creditor]'a [count] nöbet
/// borçlu. [favors] bu iki kişi arasındaki bütün iyilikler (iki yönlü,
/// eskiden yeniye).
typedef FavorDebt = ({
  String debtor,
  String creditor,
  int count,
  List<Favor> favors,
});

/// İyilik defteri (saf Dart): takas defterindeki "X yerine Y" kayıtlarından
/// kim kimin yerine geçti, kim kime borçlu. Karşılıklı takaslar iyilik
/// sayılmaz (iki taraf da gün verir). Y daha sonra X'in yerine geçerse borç
/// kapanır (net).
class FavorLedger {
  FavorLedger._(this.debts, this.favors);

  /// Net borçlar; büyükten küçüğe.
  final List<FavorDebt> debts;

  /// Bütün iyilikler, eskiden yeniye.
  final List<Favor> favors;

  /// [months]: ay → o ayın takas defteri. Yalnız aynı roldeki kişiler
  /// arasındaki değişiklikler sayılır ([roleOf] null dönerse kişi silinmiş
  /// sayılır, atlanır).
  factory FavorLedger.build(
    Map<int, List<SwapEntry>> months, {
    required Object? Function(String id) roleOf,
  }) {
    final favors = <Favor>[];
    for (final m in months.keys.toList()..sort()) {
      for (final e in months[m]!) {
        final (from, to, day) = (e.from, e.to, e.day);
        if (e.isSwap || from == null || to == null || day == null) continue;
        final role = roleOf(from);
        if (role == null || role != roleOf(to)) continue;
        favors.add((month: m, day: day, helped: from, helper: to));
      }
    }
    // Çift → (a, b) sırasıyla net: a'nın b'ye borcu (negatif: b borçlu).
    final net = <(String, String), int>{};
    final byPair = <(String, String), List<Favor>>{};
    (String, String) key(String x, String y) =>
        x.compareTo(y) < 0 ? (x, y) : (y, x);
    for (final f in favors) {
      final k = key(f.helped, f.helper);
      net[k] = (net[k] ?? 0) + (f.helped == k.$1 ? 1 : -1);
      (byPair[k] ??= []).add(f);
    }
    final debts = <FavorDebt>[
      for (final MapEntry(key: k, value: n) in net.entries)
        if (n != 0)
          (
            debtor: n > 0 ? k.$1 : k.$2,
            creditor: n > 0 ? k.$2 : k.$1,
            count: n.abs(),
            favors: byPair[k]!,
          ),
    ]..sort((a, b) => b.count.compareTo(a.count));
    return FavorLedger._(debts, favors);
  }

  /// [debtor]'un [creditor]'a net borcu (yoksa 0).
  int owes(String debtor, String creditor) {
    for (final d in debts) {
      if (d.debtor == debtor && d.creditor == creditor) return d.count;
    }
    return 0;
  }

  /// Kişi → [creditor]'a borcu (yalnız borçlular).
  Map<String, int> debtorsOf(String creditor) => {
    for (final d in debts)
      if (d.creditor == creditor) d.debtor: d.count,
  };

  /// "3 Ekim: Banu, Ayşe yerine".
  static String describe(Favor f, String Function(String) name) =>
      '${formatDayMonth(f.day, f.month)}: ${name(f.helper)}, '
      '${name(f.helped)} yerine';

  /// Paylaşılacak metin.
  String text(int year, String Function(String) name) {
    final lines = [
      '$year iyilik defteri',
      if (debts.isEmpty) 'Açık borç yok.',
      for (final d in debts) ...[
        '• ${name(d.debtor)} → ${name(d.creditor)}: ${d.count} nöbet',
        for (final f in d.favors) '   ${describe(f, name)}',
      ],
    ];
    return lines.join('\n');
  }
}
