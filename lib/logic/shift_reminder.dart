import '../models/models.dart';
import 'turkish_dates.dart';

/// Bir nöbet hatırlatması: ne zaman çalacak, hangi nöbet için.
typedef ShiftReminderItem = ({
  DateTime at,
  DateTime shiftDay,
  String shift,
  List<String> nurseIds,
  List<String> techIds,
});

/// "Kendi nöbet hatırlatmam" kuralı (saf Dart): seçilen kişinin her
/// nöbetinden önceki gün [hour]:[minute]'da bildirim.
class ShiftReminder {
  const ShiftReminder._();

  /// Varsayılan saat: önceki akşam 20:00.
  static const defaultHour = 20;

  /// [plans] içindeki, [now]'dan sonra çalacak hatırlatmalar (en fazla
  /// [count], tarih sırasıyla). 16B nöbetleri "16B", diğerleri "24".
  static List<ShiftReminderItem> upcoming({
    required DateTime now,
    required Iterable<MonthPlan> plans,
    required String personId,
    int hour = defaultHour,
    int minute = 0,
    int count = 30,
  }) {
    final items = <ShiftReminderItem>[];
    for (final plan in plans) {
      for (final a in plan.assignments.values) {
        final extra = a.extraShiftOf(personId);
        if (!a.personIds.contains(personId) && extra == null) continue;
        final day = DateTime(plan.year, plan.month, a.day);
        final at = DateTime(day.year, day.month, day.day - 1, hour, minute);
        if (!at.isAfter(now)) continue;
        items.add((
          at: at,
          shiftDay: day,
          shift: extra ?? a.shiftCode(personId),
          nurseIds: a.nurseIds,
          techIds: [?a.techId, ?a.tech16bId],
        ));
      }
    }
    items.sort((x, y) => x.at.compareTo(y.at));
    return items.take(count).toList();
  }

  /// Bildirim metni: "5 Kasım Perşembe nöbetin var (24). Hemşire: Emre,
  /// Nur · Radyoloji: Anıl".
  static String body(ShiftReminderItem item, String Function(String) name) {
    final d = item.shiftDay;
    final parts = [
      if (item.nurseIds.isNotEmpty)
        'Hemşire: ${item.nurseIds.map(name).join(', ')}',
      if (item.techIds.isNotEmpty)
        'Radyoloji: ${item.techIds.map(name).join(', ')}',
    ];
    return 'Yarın (${formatDayMonthWeekday(d.year, d.month, d.day)}) '
        'nöbetin var (${item.shift}).'
        '${parts.isEmpty ? '' : '\n${parts.join(' · ')}'}';
  }
}
