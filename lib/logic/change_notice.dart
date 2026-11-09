import '../models/models.dart';
import 'turkish_collation.dart';
import 'turkish_dates.dart';

/// Bir kişinin paylaşılan listeye göre değişen günleri.
class PersonChange {
  const PersonChange({
    required this.person,
    required this.added,
    required this.removed,
    required this.changed,
  });

  final Person person;

  /// Yeni yazılan günler → vardiya ("24", "16A", ...).
  final Map<int, String> added;

  /// Kaldırılan günler → eski vardiya.
  final Map<int, String> removed;

  /// Vardiyası değişen günler → (eski, yeni).
  final Map<int, (String, String)> changed;
}

/// Paylaşılmış listeyle şimdiki liste arasındaki kişi bazlı farklar ve
/// etkilenen kişilere gidecek mesaj (saf Dart).
class ChangeNotice {
  const ChangeNotice._();

  static Map<int, String> _codes(Map<int, DayAssignment> a, String id) => {
    for (final x in a.values)
      if (x.includes(id))
        x.day: x.shiftCode(id)
      else
        x.day: ?x.extraShiftOf(id),
  };

  static List<PersonChange> compute({
    required Map<int, DayAssignment> before,
    required Map<int, DayAssignment> after,
    required Iterable<Person> people,
  }) {
    final out = <PersonChange>[];
    for (final p in people) {
      final b = _codes(before, p.id), a = _codes(after, p.id);
      final added = {
        for (final e in a.entries)
          if (!b.containsKey(e.key)) e.key: e.value,
      };
      final removed = {
        for (final e in b.entries)
          if (!a.containsKey(e.key)) e.key: e.value,
      };
      final changed = {
        for (final e in a.entries)
          if (b[e.key] case final old? when old != e.value)
            e.key: (old, e.value),
      };
      if (added.isEmpty && removed.isEmpty && changed.isEmpty) continue;
      out.add(
        PersonChange(
          person: p,
          added: added,
          removed: removed,
          changed: changed,
        ),
      );
    }
    out.sort((x, y) => compareTurkish(x.person.name, y.person.name));
    return out;
  }

  /// Satır satır özet ("12 Ekim Pazartesi: nöbet kaldırıldı (24)").
  static List<String> lines(PersonChange c, int year, int month) {
    String d(int day) => formatDayMonthWeekday(year, month, day);
    final days = {
      ...c.added.keys,
      ...c.removed.keys,
      ...c.changed.keys,
    }.toList()..sort();
    return [
      for (final day in days)
        if (c.added[day] case final code?)
          '${d(day)}: $code yazıldı'
        else if (c.removed[day] case final code?)
          '${d(day)}: $code kaldırıldı'
        else if (c.changed[day] case (final old, final now))
          '${d(day)}: $old → $now',
    ];
  }

  /// Kişiye gidecek mesaj.
  static String message(PersonChange c, int year, int month) =>
      'Merhaba ${c.person.name}, ${turkishMonthNames[month - 1]} nöbet '
      'listesinde senin için değişiklik var:\n'
      '${lines(c, year, month).map((l) => '• $l').join('\n')}';
}
