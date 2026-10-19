import '../models/day_assignment.dart';

/// Eski (uygulama öncesi) listelerin kişi kişi girilmesi (saf Dart).
/// Geçmiş kayıt olduğu için koltuk sınırı ve kurallar uygulanmaz; girilen
/// ne ise o kaydedilir.
class PastRosterEntry {
  const PastRosterEntry._();

  /// Hemşire [personId]'nin [days] günlerindeki nöbetlerini yazar: bu
  /// günlerde hemşire olarak eklenir, ayın diğer günlerinden çıkarılır.
  /// Diğer kişilerin kayıtlarına dokunulmaz; boş kalan günler silinir.
  static Map<int, DayAssignment> setNurseDays(
    Map<int, DayAssignment> assignments, {
    required String personId,
    required Set<int> days,
    required int daysInMonth,
  }) {
    final result = <int, DayAssignment>{};
    for (var d = 1; d <= daysInMonth; d++) {
      final current = assignments[d] ?? DayAssignment(day: d);
      final nurses = [
        for (final id in current.nurseIds)
          if (id != personId) id,
        if (days.contains(d)) personId,
      ];
      final updated = current.copyWith(nurseIds: nurses);
      if (updated.personIds.isNotEmpty) result[d] = updated;
    }
    return result;
  }

  /// Kişinin hemşire olarak nöbet tuttuğu günler.
  static Set<int> nurseDaysOf(
    Map<int, DayAssignment> assignments,
    String personId,
  ) => {
    for (final a in assignments.values)
      if (a.nurseIds.contains(personId)) a.day,
  };

  /// Gün → o güne girilmiş hemşire sayısı.
  static Map<int, int> nurseCounts(Map<int, DayAssignment> assignments) => {
    for (final a in assignments.values)
      if (a.nurseIds.isNotEmpty) a.day: a.nurseIds.length,
  };
}
