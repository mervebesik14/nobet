/// Ay başı hatırlatma kuralı (saf Dart).
///
/// Ayın [startDay]. gününden itibaren gelecek ayın listesi henüz
/// oluşturulmadıysa, istenmeyen günleri ve izinleri toplamaya başlamak için
/// hatırlatılır. "Sonra" denince [snooze] boyunca susar.
class NextMonthReminder {
  const NextMonthReminder._();

  /// Hatırlatmanın başladığı gün.
  static const startDay = 17;

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
}
