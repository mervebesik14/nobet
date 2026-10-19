/// Otomatik yedeklerin saklama kuralı (saf Dart).
///
/// Veri her değiştiğinde anlık bir yedek alınır. Art arda gelen değişiklikler
/// [mergeWindow] içindeyse en yeni yedeğin üzerine yazılır; böylece kısa bir
/// düzenleme oturumu tek yedek olur, ama bir hatadan önceki durum daha eski
/// bir yedekte kalır. En fazla [maxCount] yedek tutulur, en eskiler silinir.
class AutoBackupPolicy {
  const AutoBackupPolicy._();

  static const maxCount = 20;
  static const mergeWindow = Duration(minutes: 10);

  /// [existing] yedek zamanlarına [now] anındaki yeni yedek eklenirken
  /// silinecek yedekler. En yeni yedek [mergeWindow] içindeyse o da silinir
  /// (yenisi onun yerini alır).
  static List<DateTime> toRemove(List<DateTime> existing, DateTime now) {
    final sorted = [...existing]..sort();
    final remove = <DateTime>[];
    if (sorted.isNotEmpty && now.difference(sorted.last) < mergeWindow) {
      remove.add(sorted.removeLast());
    }
    // Yenisiyle birlikte en fazla maxCount kalsın.
    final excess = sorted.length + 1 - maxCount;
    if (excess > 0) remove.addAll(sorted.take(excess));
    return remove;
  }
}
