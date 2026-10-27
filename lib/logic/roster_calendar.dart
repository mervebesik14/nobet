import 'day_shift_planner.dart';
import 'personal_roster.dart';

/// Takvime yazılacak tek etkinlik (nöbet ya da 7A).
typedef CalendarEntry = ({
  String uid,
  DateTime start,
  DateTime end,
  String title,
  String? description,
});

/// Kişinin aylık nöbetlerini telefon takvimine eklenecek bir takvim dosyası
/// (iCalendar, .ics) olarak üretir (saf Dart). iPhone ve Android takvimleri
/// dosyaya dokununca etkinlikleri ekler.
///
/// - 24 nöbet: 08:00 → ertesi gün 08:00
/// - 16B: 08:00 → 24:00
/// - 7A: 08:00 → günün mesai saati kadar (ör. 7 saat → 15:00)
///
/// Her etkinlikte önceki akşam 20:00'de hatırlatma vardır. Saatler cihazın
/// yerel saatine göredir. Etkinlik kimlikleri kişi ve güne bağlıdır; aynı
/// ayın güncel dosyası yeniden eklenince takvim uygulaması çoğunlukla eski
/// etkinliği günceller.
class RosterCalendar {
  const RosterCalendar._();

  static const mimeType = 'text/calendar';

  /// Nöbet / 7A başlama saati.
  static const startHour = 8;

  /// Hatırlatma: önceki akşam 20:00 (başlangıçtan 12 saat önce).
  static const reminderBefore = Duration(hours: 12);

  static String _two(int n) => n.toString().padLeft(2, '0');

  static String _local(DateTime t) =>
      '${t.year}${_two(t.month)}${_two(t.day)}T'
      '${_two(t.hour)}${_two(t.minute)}${_two(t.second)}';

  static String _utc(DateTime t) {
    final u = t.toUtc();
    return '${_local(u)}Z';
  }

  /// Metin değerlerinde \, ; , ve satır sonu kaçışı.
  static String _escape(String s) => s
      .replaceAll(r'\', r'\\')
      .replaceAll(';', r'\;')
      .replaceAll(',', r'\,')
      .replaceAll('\n', r'\n');

  /// Satırları 75 baytı aşmayacak şekilde katlar (devam satırı boşlukla
  /// başlar); UTF-8 karakterler bölünmez.
  static String _fold(String line) {
    final out = StringBuffer();
    var bytes = 0;
    for (final rune in line.runes) {
      final ch = String.fromCharCode(rune);
      final size = rune < 0x80
          ? 1
          : rune < 0x800
          ? 2
          : rune < 0x10000
          ? 3
          : 4;
      if (bytes + size > 75) {
        out.write('\r\n ');
        bytes = 1;
      }
      out.write(ch);
      bytes += size;
    }
    return out.toString();
  }

  /// [data] kişisinin nöbetleri ve [dayShifts] içindeki kendi 7A'ları,
  /// güne göre sıralı. Hem dosyaya hem doğrudan telefon takvimine yazılır.
  static List<CalendarEntry> events({
    required PersonalRosterData data,
    Iterable<DayShift> dayShifts = const [],
  }) {
    final person = data.person;
    final out = <(int, CalendarEntry)>[];
    void add({
      required String kind,
      required int day,
      required Duration length,
      required String title,
      String? description,
    }) {
      final start = DateTime(data.year, data.month, day, startHour);
      out.add((
        day,
        (
          uid:
              'nobetci-${person.id}-${data.year}${_two(data.month)}'
              '${_two(day)}-$kind@nobetci',
          start: start,
          end: start.add(length),
          title: title,
          description: description,
        ),
      ));
    }

    for (final s in data.shifts) {
      final is16 = s.shift == '16B';
      add(
        kind: is16 ? '16b' : '24',
        day: s.day,
        length: Duration(hours: is16 ? 16 : 24),
        title: is16 ? 'Nöbet (16B)' : 'Nöbet (24)',
        description: [
          'Hemşire: ${s.nurses.join(', ')}',
          if (s.techs.isNotEmpty) 'Radyoloji: ${s.techs.join(', ')}',
        ].join('\n'),
      );
    }
    for (final s in dayShifts) {
      if (s.personId != person.id) continue;
      add(
        kind: '7a',
        day: s.day,
        length: Duration(minutes: (s.hours * 60).round()),
        title: '7A (gündüz mesaisi)',
      );
    }
    out.sort((a, b) => a.$1.compareTo(b.$1));
    return [for (final e in out) e.$2];
  }

  /// [data] kişisinin nöbetleri ve [dayShifts] içindeki kendi 7A'ları.
  /// [now] dosyanın oluşturulma anı (DTSTAMP).
  static String ics({
    required PersonalRosterData data,
    Iterable<DayShift> dayShifts = const [],
    required DateTime now,
  }) {
    final person = data.person;
    final lines = <String>[
      'BEGIN:VCALENDAR',
      'VERSION:2.0',
      'PRODID:-//Nöbetçi//Nöbet Listesi//TR',
      'CALSCALE:GREGORIAN',
      'METHOD:PUBLISH',
      'X-WR-CALNAME:${_escape('${person.name} nöbetleri')}',
    ];

    for (final e in events(data: data, dayShifts: dayShifts)) {
      lines.addAll([
        'BEGIN:VEVENT',
        'UID:${e.uid}',
        'DTSTAMP:${_utc(now)}',
        'DTSTART:${_local(e.start)}',
        'DTEND:${_local(e.end)}',
        'SUMMARY:${_escape(e.title)}',
        if (e.description != null) 'DESCRIPTION:${_escape(e.description!)}',
        'BEGIN:VALARM',
        'ACTION:DISPLAY',
        'DESCRIPTION:${_escape(e.title)}',
        'TRIGGER:-PT${reminderBefore.inHours}H',
        'END:VALARM',
        'END:VEVENT',
      ]);
    }
    lines.add('END:VCALENDAR');
    return '${lines.map(_fold).join('\r\n')}\r\n';
  }
}
