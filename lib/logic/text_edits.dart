import '../models/models.dart';
import 'day_shift_planner.dart';
import 'roster_editor.dart';
import 'turkish_collation.dart';
import 'turkish_dates.dart';

/// Yazılı düzenleme komutu türü.
enum TextEditKind { write, remove, replace, swap }

/// Çözülmüş bir komut.
class TextEdit {
  const TextEdit.write(this.person, this.days, this.code)
    : kind = TextEditKind.write,
      other = null,
      otherDay = null;
  const TextEdit.remove(this.person, this.days)
    : kind = TextEditKind.remove,
      code = null,
      other = null,
      otherDay = null;
  const TextEdit.replace(this.person, int day, Person this.other)
    : kind = TextEditKind.replace,
      days = const [],
      code = null,
      otherDay = day;
  TextEdit.swap(this.person, int day, Person this.other, int this.otherDay)
    : kind = TextEditKind.swap,
      code = null,
      days = [day];

  final TextEditKind kind;
  final Person person;

  /// write/remove: günler; swap: [person]'ın günü.
  final List<int> days;

  /// write: "24", "16A", "16B", "7A" ya da özel mesai adı.
  final String? code;

  /// replace: yerine geçen; swap: öteki kişi.
  final Person? other;

  /// replace: gün; swap: öteki kişinin günü.
  final int? otherDay;

  /// Önizleme cümlesi.
  String describe(int month) {
    String d(int day) => formatDayMonth(day, month);
    return switch (kind) {
      TextEditKind.write => '${person.name}: ${days.map(d).join(', ')} → $code',
      TextEditKind.remove =>
        '${person.name}: ${days.map(d).join(', ')} nöbeti silinir',
      TextEditKind.replace =>
        '${d(otherDay!)}: ${person.name} yerine ${other!.name}',
      TextEditKind.swap =>
        'Takas: ${person.name} ${d(days.single)} ↔ '
            '${other!.name} ${d(otherDay!)}',
    };
  }
}

/// Bir satırın çözümü: komut ya da hata.
typedef TextEditLine = ({String text, TextEdit? edit, String? error});

/// Uygulama sonucu.
typedef TextEditResult = ({
  Map<int, DayAssignment> assignments,
  Map<String, List<int>> techDayShifts,
  List<String> done,
  List<String> errors,
});

/// Yazarak düzenleme (saf Dart): "Ayşe 12'yi Banu'yla değiştir", "Ayşe 12
/// Banu 15 takas", "Nur 26'ya 4A", "Ayşe 3 sil" gibi satırları komuta
/// çevirir ve listeye uygular. Her satır (ya da ; ile ayrılan parça) bir
/// komuttur.
class TextEdits {
  const TextEdits._();

  /// Örnek komutlar (yardım metni).
  static const examples = [
    "Ayşe 12'yi Banu'yla değiştir   (12'de Ayşe yerine Banu)",
    'Ayşe 12 Banu 15 takas   (iki nöbet yer değiştirir)',
    "Nur 26'ya 4A   (24, 16A, 16B, 7A ya da özel mesai)",
    'Ayşe 3 5 7 yaz   (24 nöbet)',
    'Ayşe 12 sil',
  ];

  static final _swapWords = {'takas', 'değiş', 'değişsin', '↔', '<->'};
  static final _replaceWords = {'değiştir', 'yerine', 'ver'};
  static final _removeWords = {'sil', 'kaldır', 'çıkar', 'çıkart'};

  /// [text] satırlarını çözer. [codes] özel mesai adları (büyük harf).
  static List<TextEditLine> parse({
    required String text,
    required Iterable<Person> people,
    required int daysInMonth,
    Iterable<String> codes = const [],
  }) {
    final out = <TextEditLine>[];
    for (final raw in text.split(RegExp(r'[\n;]'))) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      try {
        out.add((
          text: line,
          edit: _parseLine(line, people, daysInMonth, codes),
          error: null,
        ));
      } on FormatException catch (e) {
        out.add((text: line, edit: null, error: e.message));
      }
    }
    return out;
  }

  static TextEdit _parseLine(
    String line,
    Iterable<Person> people,
    int daysInMonth,
    Iterable<String> codes,
  ) {
    final codeSet = {
      '24',
      '16A',
      '16B',
      '7A',
      for (final c in codes) turkishUpperCase(c),
    };
    // Kelimeler: kesme işaretinden sonraki ek atılır ("12'yi" → "12").
    final words = [
      for (final w
          in turkishLowerCase(line)
              .replaceAll('↔', ' ↔ ')
              .replaceAll('<->', ' ↔ ')
              .split(RegExp(r'[\s,.:]+')))
        if (w.isNotEmpty) w.split(RegExp("['’]")).first,
    ];

    // Kişi adları: en uzun eşleşme (tam ad, sonra tek kelimelik ad/soyad).
    final full = <String, Person>{
      for (final p in people) normalizeName(p.name): p,
    };
    final single = <String, List<Person>>{};
    for (final p in people) {
      for (final part in normalizeName(p.name).split(' ')) {
        (single[part] ??= []).add(p);
      }
    }

    // Öğeler: kişi, gün, kod, anahtar sözcük.
    final items = <Object>[]; // Person | int (gün) | String (kod/sözcük)
    var i = 0;
    while (i < words.length) {
      var matched = false;
      for (var k = 3; k >= 2 && !matched; k--) {
        if (i + k > words.length) continue;
        final p = full[words.sublist(i, i + k).join(' ')];
        if (p != null) {
          items.add(p);
          i += k;
          matched = true;
        }
      }
      if (matched) continue;
      final w = words[i];
      i++;
      // Ekli sayı ("12yi", "26ya") da gün.
      final number = RegExp(
        r'^(\d{1,2})(\p{L}*)$',
        unicode: true,
      ).firstMatch(w);
      final upper = turkishUpperCase(w);
      if (codeSet.contains(upper) && upper != '24') {
        items.add('#$upper');
      } else if (number != null) {
        items.add(int.parse(number.group(1)!));
      } else if (single[w] ?? single[_stem(w, single.keys)] case final list?) {
        if (list.length > 1) {
          throw FormatException(
            '"$w" birden çok kişiye uyuyor '
            '(${list.map((p) => p.name).join(', ')}); soyadıyla yazın.',
          );
        }
        items.add(list.single);
      } else if (full[w] case final p?) {
        items.add(p);
      } else {
        items.add(w);
      }
    }

    final persons = items.whereType<Person>().toList();
    final words2 = items.whereType<String>().toSet();
    final numbers = items.whereType<int>().toList();
    bool has(Set<String> keys) => words2.any(
      (w) => keys.any((k) => w == k || (k.length > 2 && w.startsWith(k))),
    );
    void checkDay(int d) {
      if (d < 1 || d > daysInMonth) {
        throw FormatException('$d. gün bu ayda yok.');
      }
    }

    if (persons.isEmpty) {
      throw const FormatException('Kişi adı bulunamadı.');
    }

    if (persons.length >= 2) {
      // İki kişi: takas (iki gün) ya da değiştirme (bir gün).
      final a = persons[0], b = persons[1];
      if (numbers.length >= 2 || has(_swapWords) && numbers.length >= 2) {
        // Her kişinin günü, adından sonraki ilk sayı.
        int dayAfter(Person p) {
          final at = items.indexOf(p);
          for (var j = at + 1; j < items.length; j++) {
            if (items[j] is int) return items[j] as int;
            if (items[j] is Person) break;
          }
          throw FormatException('${p.name} için gün yazılmamış.');
        }

        final da = dayAfter(a), db = dayAfter(b);
        checkDay(da);
        checkDay(db);
        return TextEdit.swap(a, da, b, db);
      }
      if (numbers.length == 1 &&
          (has(_replaceWords) || has(_swapWords) || words2.isEmpty)) {
        checkDay(numbers.single);
        // "Banu, Ayşe yerine 12": yerine'den önceki kişi eskisi.
        final yerine = items.indexWhere(
          (x) => x is String && x.startsWith('yerine'),
        );
        if (yerine > 0 && items[yerine - 1] is Person) {
          final old = items[yerine - 1] as Person;
          final neu = old == a ? b : a;
          return TextEdit.replace(old, numbers.single, neu);
        }
        return TextEdit.replace(a, numbers.single, b);
      }
      throw const FormatException(
        "Anlaşılamadı. Ör. \"Ayşe 12'yi Banu'yla değiştir\" ya da "
        '"Ayşe 12 Banu 15 takas".',
      );
    }

    final p = persons.single;
    if (numbers.isEmpty) {
      throw FormatException('${p.name} için gün yazılmamış.');
    }
    if (has(_removeWords)) {
      numbers.forEach(checkDay);
      return TextEdit.remove(p, numbers);
    }
    var code = items
        .whereType<String>()
        .where((s) => s.startsWith('#'))
        .map((s) => s.substring(1))
        .firstOrNull;
    var days = numbers;
    // "Ayşe 3 24": birden çok sayıda sondaki 24 vardiya kodudur.
    if (code == null && numbers.length >= 2 && numbers.last == 24) {
      code = '24';
      days = numbers.sublist(0, numbers.length - 1);
    }
    days.forEach(checkDay);
    return TextEdit.write(p, days, code ?? '24');
  }

  /// [edits]'i sırayla uygular; uygulanamayanlar [TextEditResult.errors]'a
  /// yazılır, ötekiler yine uygulanır.
  static TextEditResult apply({
    required MonthPlan plan,
    required List<TextEdit> edits,
    required RosterSettings settings,
    required Iterable<Holiday> holidays,
  }) {
    var a = plan.assignments;
    final tech7a = {
      for (final e in plan.techDayShifts.entries) e.key: [...e.value],
    };
    final done = <String>[];
    final errors = <String>[];
    final custom = {for (final c in settings.customShifts) c.code: c};
    String d(int day) => formatDayMonth(day, plan.month);

    for (final e in edits) {
      final p = e.person;
      try {
        switch (e.kind) {
          case TextEditKind.replace:
            final day = e.otherDay!;
            final current = a[day];
            if (current == null || !current.includes(p.id)) {
              throw RosterEditException('${p.name} ${d(day)} nöbette değil.');
            }
            a = RosterEditor.replace(
              a,
              day: day,
              role: current.nurseIds.contains(p.id)
                  ? Role.nurse
                  : Role.radiologyTech,
              oldId: p.id,
              newId: e.other!.id,
              nursesPerDay: settings.nursesPerDay,
              secondary: current.isSecondaryTech(p.id),
            );
          case TextEditKind.swap:
            a = RosterEditor.swap(
              a,
              a: p.id,
              dayA: e.days.single,
              b: e.other!.id,
              dayB: e.otherDay!,
              role: p.role,
              nursesPerDay: settings.nursesPerDay,
            );
          case TextEditKind.remove:
            for (final day in e.days) {
              final current = a[day];
              final had7a = tech7a[p.id]?.remove(day) ?? false;
              if (current?.extraShiftOf(p.id) != null) {
                a = RosterEditor.setExtraShift(
                  a,
                  day: day,
                  personId: p.id,
                  code: null,
                );
              } else if (current != null && current.includes(p.id)) {
                a = RosterEditor.replace(
                  a,
                  day: day,
                  role: current.nurseIds.contains(p.id)
                      ? Role.nurse
                      : Role.radiologyTech,
                  oldId: p.id,
                  newId: null,
                  nursesPerDay: settings.nursesPerDay,
                  secondary: current.isSecondaryTech(p.id),
                );
              } else if (!had7a) {
                throw RosterEditException('${p.name} ${d(day)} nöbette değil.');
              }
            }
          case TextEditKind.write:
            for (final day in e.days) {
              a = _write(
                a,
                tech7a,
                plan,
                p,
                day,
                e.code!,
                custom,
                settings,
                holidays,
              );
            }
        }
        done.add(e.describe(plan.month));
      } on RosterEditException catch (x) {
        errors.add('${e.describe(plan.month)}: ${x.message}');
      }
    }
    return (
      assignments: a,
      techDayShifts: {
        for (final e in tech7a.entries)
          if (e.value.isNotEmpty) e.key: (e.value..sort()),
      },
      done: done,
      errors: errors,
    );
  }

  static Map<int, DayAssignment> _write(
    Map<int, DayAssignment> a,
    Map<String, List<int>> tech7a,
    MonthPlan plan,
    Person p,
    int day,
    String code,
    Map<String, CustomShift> custom,
    RosterSettings settings,
    Iterable<Holiday> holidays,
  ) {
    final current = a[day] ?? DayAssignment(day: day);
    final onShift = current.includes(p.id);
    String d() => formatDayMonth(day, plan.month);

    // Koltuğa oturt (yoksa boş koltuğa).
    Map<int, DayAssignment> seat(Map<int, DayAssignment> a) {
      final c = a[day] ?? DayAssignment(day: day);
      if (c.includes(p.id) && !c.isSecondaryTech(p.id)) return a;
      if (p.role == Role.nurse) {
        if (c.nurseIds.length >= settings.nursesPerDay) {
          throw RosterEditException(
            '${d()} hemşire koltukları dolu; "X $day yerine ${p.name}" '
            'yazın.',
          );
        }
        return RosterEditor.replace(
          a,
          day: day,
          role: Role.nurse,
          newId: p.id,
          nursesPerDay: settings.nursesPerDay,
        );
      }
      if (c.techId != null && c.techId != p.id) {
        throw RosterEditException(
          '${d()} tekniker koltuğu dolu; "X $day yerine ${p.name}" yazın.',
        );
      }
      return RosterEditor.setTechSeat(
        a,
        day: day,
        personId: p.id,
        secondary: false,
      );
    }

    // Aynı gün 7A ve ek mesai, nöbete yazılınca düşer.
    void drop7a() => tech7a[p.id]?.remove(day);

    switch (code) {
      case '24':
        drop7a();
        var next = seat(a);
        if (next[day]!.is16a(p.id)) {
          next = RosterEditor.set16a(
            next,
            day: day,
            personId: p.id,
            night: false,
          );
        }
        if (next[day]!.customShiftOf(p.id) != null) {
          next = RosterEditor.setCustomShift(
            next,
            day: day,
            personId: p.id,
            code: null,
          );
        }
        return next;
      case '16A':
        drop7a();
        return RosterEditor.set16a(
          seat(a),
          day: day,
          personId: p.id,
          night: true,
        );
      case '16B':
        if (p.role != Role.radiologyTech) {
          throw const RosterEditException('16B yalnız teknikere yazılır.');
        }
        drop7a();
        return RosterEditor.setTechSeat(
          a,
          day: day,
          personId: p.id,
          secondary: true,
        );
      case '7A':
        if (DayShiftPlanner.workdayHours(
              year: plan.year,
              month: plan.month,
              day: day,
              holidays: holidays,
              settings: settings,
            ) ==
            null) {
          throw RosterEditException('${d()} mesai günü değil; 7A yazılmaz.');
        }
        var next = a;
        if (onShift) {
          next = RosterEditor.replace(
            next,
            day: day,
            role: current.nurseIds.contains(p.id)
                ? Role.nurse
                : Role.radiologyTech,
            oldId: p.id,
            newId: null,
            nursesPerDay: settings.nursesPerDay,
            secondary: current.isSecondaryTech(p.id),
          );
        }
        tech7a[p.id] = {...?tech7a[p.id], day}.toList();
        return next;
      default:
        final def = custom[code];
        if (def == null) {
          throw RosterEditException('"$code" diye bir mesai tanımlı değil.');
        }
        drop7a();
        if (def.fillsSeat) {
          return RosterEditor.setCustomShift(
            seat(a),
            day: day,
            personId: p.id,
            code: code,
          );
        }
        var next = a;
        if (onShift) {
          next = RosterEditor.replace(
            next,
            day: day,
            role: current.nurseIds.contains(p.id)
                ? Role.nurse
                : Role.radiologyTech,
            oldId: p.id,
            newId: null,
            nursesPerDay: settings.nursesPerDay,
            secondary: current.isSecondaryTech(p.id),
          );
        }
        return RosterEditor.setExtraShift(
          next,
          day: day,
          personId: p.id,
          code: code,
        );
    }
  }

  static const _suffixes = [
    'nın',
    'nin',
    'nun',
    'nün',
    'yla',
    'yle',
    'yı',
    'yi',
    'yu',
    'yü',
    'ya',
    'ye',
    'ın',
    'in',
    'un',
    'ün',
    'la',
    'le',
    'ı',
    'i',
    'u',
    'ü',
    'a',
    'e',
  ];

  /// Kesme işaretsiz yazılan ekli adı ("banuyla") bilinen ada indirger.
  static String _stem(String word, Iterable<String> known) {
    final set = known.toSet();
    for (final s in _suffixes) {
      if (word.length > s.length + 1 && word.endsWith(s)) {
        final base = word.substring(0, word.length - s.length);
        if (set.contains(base)) return base;
      }
    }
    return word;
  }
}
