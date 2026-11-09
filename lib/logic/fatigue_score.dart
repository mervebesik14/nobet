import 'person_totals.dart';

/// Yorgunluk puanının bir bileşeni.
typedef FatiguePart = ({String label, num count, double points});

/// Yorgunluk puanı (saf Dart): nöbet sayısı, gün aşırı ve art arda
/// nöbetler, hafta sonu ve art arda hafta sonları, tatil/bayram nöbetleri
/// tek bir sayıda toplanır. Ağırlıklar [weights]'te; yüksek puan daha
/// yıpratıcı bir ay/yıl demektir.
class FatigueScore {
  const FatigueScore._();

  static const perShift = 1.0;
  static const perEveryOtherDayPair = 1.0;
  static const perConsecutivePair = 2.0;
  static const perWeekendShift = 0.5;
  static const perConsecutiveWeekend = 1.0;
  static const perHolidayShift = 0.5;

  /// Puanın açıklaması (Ayarlar/yardım metni).
  static const weights =
      'Her nöbet 1, gün aşırı her çift +1, art arda her çift +2, hafta '
      'sonu nöbeti +0,5, art arda hafta sonu +1, tatil/bayram nöbeti +0,5.';

  /// Ayın hafta sonları: her biri o haftanın Cumartesi ve/veya Pazar
  /// günleri (ay başı/sonunda tek gün olabilir), sıralı.
  static List<List<int>> weekendBlocks(int year, int month) {
    final days = DateTime(year, month + 1, 0).day;
    final out = <List<int>>[];
    for (var d = 1; d <= days; d++) {
      final w = DateTime(year, month, d).weekday;
      if (w == DateTime.saturday) {
        out.add([d, if (d + 1 <= days) d + 1]);
      } else if (w == DateTime.sunday && d == 1) {
        out.add([d]);
      }
    }
    return out;
  }

  /// Art arda iki hafta sonunda da nöbet tutulan durum sayısı.
  static int consecutiveWeekends(Set<int> days, List<List<int>> blocks) {
    var count = 0;
    for (var i = 0; i + 1 < blocks.length; i++) {
      if (blocks[i].any(days.contains) && blocks[i + 1].any(days.contains)) {
        count++;
      }
    }
    return count;
  }

  /// Art arda gün çifti sayısı (d ve d+1'de nöbet).
  static int consecutivePairs(Set<int> days) =>
      days.where((d) => days.contains(d + 1)).length;

  /// Bileşenler (puanı 0 olanlar dahil).
  static List<FatiguePart> parts(PersonTotals t) {
    final holidays = t.nationalHolidayShifts + t.religiousHolidayShifts;
    return [
      (label: 'Nöbet', count: t.shifts, points: t.shifts * perShift),
      (
        label: 'Gün aşırı çift',
        count: t.everyOtherDayPairs,
        points: t.everyOtherDayPairs * perEveryOtherDayPair,
      ),
      (
        label: 'Art arda nöbet',
        count: t.consecutivePairs,
        points: t.consecutivePairs * perConsecutivePair,
      ),
      (
        label: 'Hafta sonu nöbeti',
        count: t.weekendShifts,
        points: t.weekendShifts * perWeekendShift,
      ),
      (
        label: 'Art arda hafta sonu',
        count: t.consecutiveWeekends,
        points: t.consecutiveWeekends * perConsecutiveWeekend,
      ),
      (
        label: 'Tatil / bayram nöbeti',
        count: holidays,
        points: holidays * perHolidayShift,
      ),
    ];
  }

  static double of(PersonTotals t) =>
      parts(t).fold(0.0, (s, p) => s + p.points);
}
