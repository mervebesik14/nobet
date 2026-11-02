import '../models/models.dart';
import 'turkish_dates.dart';

/// Takas defterinde bir kayıt: iki kişinin gün değişimi ya da bir günde
/// birinin yerine başkasının yazılması (ya da yalnız ekleme / çıkarma).
class SwapEntry {
  const SwapEntry.swap({
    required this.at,
    required String this.a,
    required int this.dayA,
    required String this.b,
    required int this.dayB,
  }) : day = null,
       from = null,
       to = null;

  const SwapEntry.change({
    required this.at,
    required int this.day,
    this.from,
    this.to,
  }) : a = null,
       dayA = null,
       b = null,
       dayB = null;

  final DateTime at;

  // Takas: a dayA'yı b'ye, b dayB'yi a'ya verdi.
  final String? a;
  final int? dayA;
  final String? b;
  final int? dayB;

  // Değişiklik: day gününde from yerine to (biri boş olabilir).
  final int? day;
  final String? from;
  final String? to;

  bool get isSwap => a != null;

  /// "Ayşe 3 Ekim ↔ Banu 4 Ekim" / "5 Ekim: Cemile yerine Derya".
  String describe(int month, String Function(String) name) {
    if (isSwap) {
      return '${name(a!)} ${formatDayMonth(dayA!, month)} ↔ '
          '${name(b!)} ${formatDayMonth(dayB!, month)}';
    }
    final date = formatDayMonth(day!, month);
    return switch ((from, to)) {
      (final f?, final t?) => '$date: ${name(f)} yerine ${name(t)}',
      (null, final t?) => '$date: ${name(t)} eklendi',
      (final f?, null) => '$date: ${name(f)} çıkarıldı',
      _ => date,
    };
  }
}

/// Ay içindeki elle nöbet değişikliklerinin defteri (saf Dart): değişiklik
/// geçmişindeki her kaydın öncesi ile sonrası karşılaştırılır. Liste
/// oluşturma, sıfırlama ve boş liste açma toplu değişiklik olduğu için
/// sayılmaz; yalnız 7A değişiklikleri de (nöbet değişmez) çıkmaz.
class SwapLog {
  const SwapLog._();

  static const _bulkTitles = {
    'Liste oluşturuldu',
    'Liste yeniden oluşturuldu',
    'Liste sıfırlandı',
    'Elle giriş için boş liste açıldı',
  };

  /// [edits] eskiden yeniye; her kaydın "sonrası" bir sonrakinin öncesi,
  /// sonuncununki [current]. Kayıtlar eskiden yeniye.
  static List<SwapEntry> build(
    List<RosterEdit> edits,
    Map<int, DayAssignment> current,
  ) {
    final out = <SwapEntry>[];
    for (var i = 0; i < edits.length; i++) {
      final edit = edits[i];
      if (_bulkTitles.contains(edit.title)) continue;
      final after = i + 1 < edits.length ? edits[i + 1].before : current;
      out.addAll(_diff(edit.at, edit.before, after));
    }
    return out;
  }

  static List<SwapEntry> _diff(
    DateTime at,
    Map<int, DayAssignment> before,
    Map<int, DayAssignment> after,
  ) {
    final days = {...before.keys, ...after.keys}.toList()..sort();
    final removed = <String, List<int>>{};
    final added = <String, List<int>>{};
    for (final d in days) {
      final was = before[d]?.personIds ?? const <String>[];
      final now = after[d]?.personIds ?? const <String>[];
      for (final id in was) {
        if (!now.contains(id)) (removed[id] ??= []).add(d);
      }
      for (final id in now) {
        if (!was.contains(id)) (added[id] ??= []).add(d);
      }
    }

    final out = <SwapEntry>[];
    // Takas: a x'i bırakıp y'yi aldı, b y'yi bırakıp x'i aldı.
    for (final a in removed.keys.toList()) {
      for (final x in [...?removed[a]]) {
        String? partner;
        int? y;
        for (final b in removed.keys) {
          if (b == a) continue;
          for (final cand in removed[b]!) {
            if ((added[a]?.contains(cand) ?? false) &&
                (added[b]?.contains(x) ?? false)) {
              partner = b;
              y = cand;
              break;
            }
          }
          if (partner != null) break;
        }
        if (partner == null || y == null) continue;
        out.add(SwapEntry.swap(at: at, a: a, dayA: x, b: partner, dayB: y));
        removed[a]!.remove(x);
        added[a]!.remove(y);
        removed[partner]!.remove(y);
        added[partner]!.remove(x);
      }
    }

    // Kalanlar gün gün: çıkanla gireni eşleştir.
    for (final d in days) {
      final outs = [
        for (final e in removed.entries)
          if (e.value.contains(d)) e.key,
      ];
      final ins = [
        for (final e in added.entries)
          if (e.value.contains(d)) e.key,
      ];
      final pairs = outs.length < ins.length ? outs.length : ins.length;
      for (var i = 0; i < pairs; i++) {
        out.add(SwapEntry.change(at: at, day: d, from: outs[i], to: ins[i]));
      }
      for (final f in outs.skip(pairs)) {
        out.add(SwapEntry.change(at: at, day: d, from: f));
      }
      for (final t in ins.skip(pairs)) {
        out.add(SwapEntry.change(at: at, day: d, to: t));
      }
    }
    return out;
  }

  /// Paylaşılacak metin.
  static String text({
    required int year,
    required int month,
    required List<SwapEntry> entries,
    required String Function(String) name,
  }) {
    final lines = [
      '${turkishMonthNames[month - 1]} $year takas defteri',
      if (entries.isEmpty) 'Bu ay elle değişiklik yok.',
      for (final e in entries) '• ${e.describe(month, name)}',
    ];
    return lines.join('\n');
  }
}
