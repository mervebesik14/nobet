/// Ay başı hatırlatma kuralı (saf Dart).
///
/// Ayın seçilen gününden (varsayılan [defaultDay]) itibaren gelecek ayın
/// listesi henüz oluşturulmadıysa, istenmeyen günleri ve izinleri toplamaya
/// başlamak için hatırlatılır. "Sonra" denince [snooze] boyunca susar.
/// Ayrıca her ayın o günü [notifyHour]'da telefon bildirimi gelir
/// ([notifications]).
class NextMonthReminder {
  const NextMonthReminder._();

  /// Hatırlatmanın varsayılan günü.
  static const defaultDay = 16;

  /// Seçilebilecek en geç gün: her ayda bulunsun diye 28.
  static const maxDay = 28;

  /// Seçilen günü 1 … [maxDay] aralığına çeker.
  static int clampDay(int day) => day.clamp(1, maxDay);

  /// "16'sı", "1'i", "20'si" gibi: ayın günü, iyelik ekiyle.
  static String dayLabel(int day) {
    final suffix = switch (day % 10) {
      0 => day == 10 || day == 30 ? 'u' : 'si', // on'u, yirmi'si, otuz'u
      1 || 5 || 8 => 'i',
      2 || 7 => 'si',
      3 || 4 => 'ü',
      6 => 'sı',
      _ => 'u', // 9
    };
    return "$day'$suffix";
  }

  /// Bildirimin varsayılan saati (yerel saat, 10:00).
  static const notifyHour = 10;

  /// "09:05" gibi.
  static String timeLabel(int hour, int minute) =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

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
    int day = defaultDay,
  }) {
    if (!hasPeople || nextMonthHasRoster || viewingNextMonth) return false;
    if (today.day < clampDay(day)) return false;
    return snoozedUntil == null || !_day(today).isBefore(_day(snoozedUntil));
  }

  /// [now]'dan sonraki bildirimler, en fazla [count] tane: her ayın
  /// [day]. günü [hour]:[minute]'da, ertesi ayın ([month]) listesi
  /// oluşturulmadıysa. Uygulama açılınca ve listeler değişince yeniden
  /// kurulur; listesi oluşturulan ayın bildirimi düşer.
  static List<({DateTime at, DateTime month})> notifications({
    required DateTime now,
    required bool Function(int year, int month) hasRoster,
    int count = 3,
    int day = defaultDay,
    int hour = notifyHour,
    int minute = 0,
  }) {
    final result = <({DateTime at, DateTime month})>[];
    for (var i = 0; i < 24 && result.length < count; i++) {
      final at = DateTime(now.year, now.month + i, clampDay(day), hour, minute);
      if (!at.isAfter(now)) continue;
      final month = DateTime(at.year, at.month + 1);
      if (hasRoster(month.year, month.month)) continue;
      result.add((at: at, month: month));
    }
    return result;
  }
}
