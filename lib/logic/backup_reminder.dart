/// Yedek hatırlatma kuralı (saf Dart).
///
/// Veriler yalnızca telefonda durduğu için, kayıtlı veri varken en son
/// yedeğin üzerinden [interval] geçtiyse (ya da hiç yedek alınmadıysa)
/// hatırlatılır. Kullanıcı "Sonra" derse [snoozedUntil] gününe kadar susar.
class BackupReminder {
  const BackupReminder._();

  /// Hatırlatma aralığı.
  static const interval = Duration(days: 14);

  /// "Sonra" denince susma süresi.
  static const snooze = Duration(days: 7);

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Bugün hatırlatılmalı mı?
  static bool isDue({
    required DateTime today,
    required bool hasData,
    DateTime? lastBackup,
    DateTime? snoozedUntil,
  }) {
    if (!hasData) return false;
    final now = _day(today);
    if (snoozedUntil != null && now.isBefore(_day(snoozedUntil))) return false;
    if (lastBackup == null) return true;
    return now.difference(_day(lastBackup)) >= interval;
  }

  /// Son yedekten bu yana geçen gün (hiç yoksa null).
  static int? daysSince(DateTime today, DateTime? lastBackup) =>
      lastBackup == null
      ? null
      : _day(today).difference(_day(lastBackup)).inDays;
}
