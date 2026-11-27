/// Bir yıllık izin bloğu ve önündeki/arkasındaki boşluk günleri.
/// Boşluk: izinden hemen önce ve hemen sonra kişinin hiç çalışmadığı
/// (nöbet, 7A, ek mesai yok; başka izin ya da pasif değil) art arda
/// günler; hafta sonu, tatil, nöbet ertesi ve nöbet izni günleri. Örnek:
/// Pazartesi–Cuma 5 iş günü izin, önceki ve sonraki hafta sonu boş → 5 +
/// 4 = 9 gün.
class LeaveStretch {
  const LeaveStretch({
    required this.start,
    required this.leaveStart,
    required this.leaveEnd,
    required this.end,
    required this.leaveWorkdays,
  });

  /// Boşluklar dahil ilk ve son gün.
  final DateTime start;
  final DateTime end;

  /// İzin bloğunun ilk ve son günü (araya giren boş günler dahil).
  final DateTime leaveStart;
  final DateTime leaveEnd;

  /// Bloktaki yıllık izin iş günü sayısı.
  final int leaveWorkdays;

  /// Boşluklar dahil toplam gün.
  int get totalDays => _days(start, end) + 1;

  /// İzin iş günleri dışındaki günler (önü, arkası, arada kalan hafta
  /// sonu ve tatiller).
  int get gapDays => totalDays - leaveWorkdays;

  int get gapBefore => _days(start, leaveStart);
  int get gapAfter => _days(leaveEnd, end);

  static int _days(DateTime a, DateTime b) => DateTime.utc(
    b.year,
    b.month,
    b.day,
  ).difference(DateTime.utc(a.year, a.month, a.day)).inDays;

  @override
  bool operator ==(Object other) =>
      other is LeaveStretch &&
      other.start == start &&
      other.leaveStart == leaveStart &&
      other.leaveEnd == leaveEnd &&
      other.end == end &&
      other.leaveWorkdays == leaveWorkdays;

  @override
  int get hashCode =>
      Object.hash(start, leaveStart, leaveEnd, end, leaveWorkdays);

  @override
  String toString() =>
      'LeaveStretch($start, $leaveStart–$leaveEnd, $end, $leaveWorkdays)';
}

/// Yıllık izin bloklarını boşluklarıyla birlikte çıkarır (saf Dart).
class LeaveStretches {
  const LeaveStretches._();

  /// Boşluk arama sınırı (her yöne); boşluk kuralı zaten 5 günü aşmaz.
  static const maxGap = 14;

  /// [leaveDays]: yıllık izin günleri. [isFree]: o gün kişi hiç çalışmıyor
  /// ve başka izinde değilse true, çalışıyor ya da başka izindeyse false,
  /// bilinmiyorsa (o ayın listesi yok) null; null'da boşluk durur.
  /// [isWorkday]: iş günü mü (yıllık izinden düşülen gün). İki izin
  /// arasında yalnız boş günler varsa tek blok sayılır.
  static List<LeaveStretch> build({
    required Iterable<DateTime> leaveDays,
    required bool? Function(DateTime day) isFree,
    required bool Function(DateTime day) isWorkday,
  }) {
    DateTime norm(DateTime d) => DateTime(d.year, d.month, d.day);
    DateTime add(DateTime d, int n) => DateTime(d.year, d.month, d.day + n);
    final days = {for (final d in leaveDays) norm(d)}.toList()..sort();
    if (days.isEmpty) return const [];

    // Blokları kur: aradaki günlerin hepsi boşsa birleştir.
    final blocks = <List<DateTime>>[];
    for (final d in days) {
      if (blocks.isNotEmpty) {
        final last = blocks.last.last;
        var joined = true;
        for (var x = add(last, 1); x.isBefore(d); x = add(x, 1)) {
          if (isFree(x) != true) {
            joined = false;
            break;
          }
        }
        if (joined) {
          blocks.last.add(d);
          continue;
        }
      }
      blocks.add([d]);
    }

    return [
      for (final b in blocks)
        () {
          var start = b.first;
          for (var i = 0; i < maxGap; i++) {
            final prev = add(start, -1);
            if (isFree(prev) != true) break;
            start = prev;
          }
          var end = b.last;
          for (var i = 0; i < maxGap; i++) {
            final next = add(end, 1);
            if (isFree(next) != true) break;
            end = next;
          }
          return LeaveStretch(
            start: start,
            leaveStart: b.first,
            leaveEnd: b.last,
            end: end,
            leaveWorkdays: b.where(isWorkday).length,
          );
        }(),
    ];
  }
}
