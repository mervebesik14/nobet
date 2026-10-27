/// Ay başı hatırlatma kuralı (saf Dart).
///
/// Ayın seçilen gününden (varsayılan [defaultDay]) itibaren gelecek ayın
/// listesi henüz oluşturulmadıysa, istenmeyen günleri ve izinleri toplamaya
/// başlamak için hatırlatılır. "Sonra" denince [snooze] boyunca susar,
/// "Başladım" denince o ay için hiç çıkmaz. Ayrıca o gün seçilen saatte
/// telefon bildirimi gelir ve "Başladım" denene ya da liste oluşturulana
/// kadar seçilen aralıkla tekrarlar ([notifications]).
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

  /// Seçilebilen tekrar aralıkları (saat). 24'ten kısa olanlar gece
  /// ([quietFrom] ile seçilen saat arası) susar.
  static const intervals = [3, 6, 12, 24, 48, 72];

  /// Varsayılan tekrar: her gün.
  static const defaultInterval = 24;

  /// Saatlik tekrarlarda bu saatten sonra o gün bildirim gelmez.
  static const quietFrom = 22;

  /// "3 saatte bir", "Her gün", "2 günde bir".
  static String intervalLabel(int hours) => hours < 24
      ? '$hours saatte bir'
      : hours == 24
      ? 'Her gün'
      : '${hours ~/ 24} günde bir';

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
    bool acknowledged = false,
    bool viewingNextMonth = false,
    DateTime? snoozedUntil,
    int day = defaultDay,
  }) {
    if (!hasPeople || nextMonthHasRoster || acknowledged || viewingNextMonth) {
      return false;
    }
    if (today.day < clampDay(day)) return false;
    return snoozedUntil == null || !_day(today).isBefore(_day(snoozedUntil));
  }

  /// [now]'dan sonraki bildirimler, en fazla [count] tane. Her ayın [day].
  /// günü [hour]:[minute]'da başlar, ertesi ayın ([month]) listesi
  /// oluşturulana ya da "Başladım" ([acknowledged]) denene kadar
  /// [intervalHours] aralıkla tekrarlar (en geç o ay başlayana kadar). Uygulama açılınca ve listeler değişince yeniden kurulur.
  static List<({DateTime at, DateTime month})> notifications({
    required DateTime now,
    required bool Function(int year, int month) hasRoster,
    bool Function(int year, int month)? acknowledged,
    int count = 3,
    int day = defaultDay,
    int hour = notifyHour,
    int minute = 0,
    int intervalHours = defaultInterval,
  }) {
    final d = clampDay(day);
    final result = <({DateTime at, DateTime month})>[];
    for (var i = 0; i < 24 && result.length < count; i++) {
      final start = DateTime(now.year, now.month + i, d, hour, minute);
      // Liste ayı başlayınca tekrar durur.
      final month = DateTime(start.year, start.month + 1);
      final end = month;
      if (!end.isAfter(now)) continue;
      if (hasRoster(month.year, month.month)) continue;
      if (acknowledged?.call(month.year, month.month) ?? false) continue;
      void add(DateTime at) {
        if (at.isAfter(now) && result.length < count) {
          result.add((at: at, month: month));
        }
      }

      if (intervalHours >= 24) {
        final step = intervalHours ~/ 24;
        for (
          var t = start;
          t.isBefore(end) && result.length < count;
          t = DateTime(t.year, t.month, t.day + step, hour, minute)
        ) {
          add(t);
        }
      } else {
        // Her gün seçilen saatten başlayıp gece susarak.
        for (
          var day = start;
          day.isBefore(end) && result.length < count;
          day = DateTime(day.year, day.month, day.day + 1, hour, minute)
        ) {
          for (
            var t = day;
            t.day == day.day &&
                (t == day || t.hour < quietFrom) &&
                t.isBefore(end);
            t = t.add(Duration(hours: intervalHours))
          ) {
            add(t);
          }
        }
      }
    }
    return result;
  }
}
