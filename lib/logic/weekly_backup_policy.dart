/// Haftalık dosya yedeği kuralı (saf Dart): Dosyalar uygulamasında görünen
/// klasöre en son yedekten [interval] geçmişse yeni yedek yazılır; en yeni
/// [keep] dosya tutulur. Dosya adı tarihten çıkar:
/// `nobetci-yedek-2026-11-01.json`.
class WeeklyBackupPolicy {
  const WeeklyBackupPolicy._();

  static const interval = Duration(days: 7);
  static const keep = 8;
  static const _prefix = 'nobetci-yedek-';

  static String _two(int n) => n.toString().padLeft(2, '0');

  /// [day] günü yazılacak dosyanın adı.
  static String fileName(DateTime day) =>
      '$_prefix${day.year}-${_two(day.month)}-${_two(day.day)}.json';

  /// Dosya adından tarih; bu kurala ait değilse null.
  static DateTime? dateOf(String fileName) {
    final m = RegExp(
      r'^nobetci-yedek-(\d{4})-(\d{2})-(\d{2})\.json$',
    ).firstMatch(fileName);
    if (m == null) return null;
    return DateTime(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
  }

  /// [existing] dosya adları varken [now] anında yedek yazılmalı mı?
  static bool isDue(Iterable<String> existing, DateTime now) {
    final dates = existing.map(dateOf).whereType<DateTime>().toList()..sort();
    if (dates.isEmpty) return true;
    final today = DateTime(now.year, now.month, now.day);
    return !today.isBefore(dates.last.add(interval));
  }

  /// Yeni dosya da sayılarak silinecek eski dosyalar (en eskiler).
  static List<String> toRemove(Iterable<String> existing) {
    final ours = [
      for (final f in existing)
        if (dateOf(f) != null) f,
    ]..sort();
    final excess = ours.length - keep;
    return excess > 0 ? ours.take(excess).toList() : const [];
  }

  /// En son yedeğin tarihi.
  static DateTime? latest(Iterable<String> existing) {
    final dates = existing.map(dateOf).whereType<DateTime>().toList()..sort();
    return dates.isEmpty ? null : dates.last;
  }
}
