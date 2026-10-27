/// Ay başı hatırlatma kuralı (saf Dart).
///
/// Ayın [startDay]. gününden itibaren gelecek ayın listesi henüz
/// oluşturulmadıysa, istenmeyen günleri ve izinleri toplamaya başlamak için
/// hatırlatılır. "Sonra" denince [snooze] boyunca susar. Ayrıca her ayın
/// [startDay]. günü [notifyHour]'da telefon bildirimi gelir
/// ([notifications]).
class NextMonthReminder {
  const NextMonthReminder._();

  /// Hatırlatmanın başladığı gün.
  static const startDay = 16;

  /// Bildirimin saati (yerel saat).
  static const notifyHour = 10;

  /// "Sonra" denince susma süresi.
  static const snooze = Duration(days: 3);

  /// [today]'den sonraki ayın ilk günü.
  static DateTime nextMonth(DateTime today) =>
      DateTime(today.year, today.month + 1);

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Bugün hatırlatılmalı mı? [viewingNextMonth]: ekranda zaten gelecek ay
  /// açık (hatırlatmaya gerek yok).
  static bool isDue({
    required DateTime today,
    required bool hasPeople,
    required bool nextMonthHasRoster,
    bool viewingNextMonth = false,
    DateTime? snoozedUntil,
  }) {
    if (!hasPeople || nextMonthHasRoster || viewingNextMonth) return false;
    if (today.day < startDay) return false;
    return snoozedUntil == null || !_day(today).isBefore(_day(snoozedUntil));
  }

  /// [now]'dan sonraki bildirimler, en fazla [count] tane: her ayın
  /// [startDay]. günü [notifyHour]'da, ertesi ayın ([month]) listesi
  /// oluşturulmadıysa. Uygulama açılınca ve listeler değişince yeniden
  /// kurulur; listesi oluşturulan ayın bildirimi düşer.
  static List<({DateTime at, DateTime month})> notifications({
    required DateTime now,
    required bool Function(int year, int month) hasRoster,
    int count = 3,
  }) {
    final result = <({DateTime at, DateTime month})>[];
    for (var i = 0; i < 24 && result.length < count; i++) {
      final at = DateTime(now.year, now.month + i, startDay, notifyHour);
      if (!at.isAfter(now)) continue;
      final month = DateTime(at.year, at.month + 1);
      if (hasRoster(month.year, month.month)) continue;
      result.add((at: at, month: month));
    }
    return result;
  }
}
