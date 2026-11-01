import '../models/models.dart';
import 'turkish_collation.dart';
import 'turkish_dates.dart';

/// Bir kişinin mesajdan okunan istekleri.
class PersonRequest {
  const PersonRequest({
    this.unavailable = const {},
    this.leaves = const {},
    this.overtime = false,
  });

  /// Nöbet tutamayacağı günler.
  final Set<int> unavailable;

  /// İzin türü → günler.
  final Map<LeaveType, Set<int>> leaves;

  /// "Fazla mesai istiyorum" yazdı mı?
  final bool overtime;

  bool get isEmpty =>
      unavailable.isEmpty && leaves.values.every((d) => d.isEmpty) && !overtime;

  PersonRequest merge(PersonRequest other) => PersonRequest(
    unavailable: {...unavailable, ...other.unavailable},
    leaves: {
      for (final t in LeaveType.values)
        if ({...?leaves[t], ...?other.leaves[t]}.isNotEmpty)
          t: {...?leaves[t], ...?other.leaves[t]},
    },
    overtime: overtime || other.overtime,
  );
}

/// Yapıştırılan cevapların okunmuş hâli.
class RequestParseResult {
  const RequestParseResult({
    required this.requests,
    required this.replied,
    required this.unmatched,
    required this.warnings,
  });

  /// Kişi kimliği → istekler (yalnız bir şey yazanlar).
  final Map<String, PersonRequest> requests;

  /// Mesajı bulunan herkes ("yok" diyenler dahil).
  final Set<String> replied;

  /// Kime ait olduğu anlaşılamayan satırlar.
  final List<String> unmatched;

  /// Atlanan günler vb.
  final List<String> warnings;
}

/// Nöbet isteklerini toplama: kişilere gönderilecek mesaj ve gelen
/// cevapları (WhatsApp'tan kopyalanan yazışma ya da "Ad: 3, 5" satırları)
/// istenmeyen gün, izin ve fazla mesai isteğine çeviren okuyucu (saf Dart).
///
/// Okunan biçimler:
/// - WhatsApp iPhone: `[12.11.2026 14:03:12] Emre Dinç: 3, 5 olmaz`
/// - WhatsApp Android: `12.11.2026 14:03 - Emre Dinç: 3, 5 olmaz`
/// - Elle: `Emre Dinç: 3, 5` ya da `Emre: 3 5` (ad tekse)
/// Gönderen satırı olmayan satırlar bir önceki mesajın devamı sayılır.
///
/// Mesaj içinde: `3, 7, 12-14` (aralık), `12 Aralık` (başka ayın adı
/// geçen günler atlanır), `izin 20-24` / `yıllık`, `şua 5-9`, `rapor 2`,
/// `fazla mesai istiyorum`. Anahtar sözcük kendinden sonraki günlere
/// geçer; `olmaz`, `tutamam`, `istemiyorum` gibi sözcükler önündeki
/// (aynı virgül grubundaki) günleri yeniden istenmeyen gün yapar.
class RequestParser {
  const RequestParser._();

  /// "3, 7, 12–14" gibi: üç ve daha uzun art arda günler aralık olarak.
  static String compactDays(Iterable<int> days) {
    final sorted = days.toSet().toList()..sort();
    final parts = <String>[];
    for (var i = 0; i < sorted.length; i++) {
      var j = i;
      while (j + 1 < sorted.length && sorted[j + 1] == sorted[j] + 1) {
        j++;
      }
      parts.add(
        j - i >= 2
            ? '${sorted[i]}–${sorted[j]}'
            : [for (var k = i; k <= j; k++) '${sorted[k]}'].join(', '),
      );
      i = j;
    }
    return parts.join(', ');
  }

  /// Kişilere gönderilecek hazır mesaj.
  static String message({required int year, required int month}) {
    final name = turkishMonthNames[month - 1];
    return 'Merhaba, $name $year nöbet listesini hazırlıyorum. '
        'Nöbet tutamayacağın günleri gün numarasıyla yazar mısın? '
        '(ör. 3, 7, 12-14)\n'
        'İzin varsa: izin 20-24\n'
        'Şua izni: şua 5-9 · Rapor: rapor 2-3\n'
        'Fazla mesai istiyorsan: fazla mesai istiyorum\n'
        'Uygun olmayan gün yoksa: yok';
  }

  // [12.11.2026 14:03:12] ya da [14:03, 12.11.2026] öneki.
  static final _bracketPrefix = RegExp(r'^\s*\[[^\]]*\]\s*');

  // 12.11.2026 14:03 - / 12/11/26, 14:03 - öneki (Android).
  static final _dashPrefix = RegExp(
    r'^\s*\d{1,2}[./]\d{1,2}[./]\d{2,4},?\s+\d{1,2}:\d{2}(?::\d{2})?\s*-\s*',
  );

  /// Önündeki günleri istenmeyen gün yapan sözcük başları.
  static const _unavailableWords = [
    'olmaz',
    'tutama',
    'istemiyor',
    'istemem',
    'gelemem',
    'gelemiyor',
    'müsait değil',
    'uygun değil',
  ];

  static const _leaveWords = {
    'yıllık': LeaveType.annual,
    'izin': LeaveType.annual,
    'şua': LeaveType.radiation,
    'rapor': LeaveType.sick,
  };

  static RequestParseResult parse({
    required String text,
    required Iterable<Person> people,
    required int year,
    required int month,
  }) {
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final byFull = <String, Person?>{};
    final byFirst = <String, Person?>{};
    for (final p in people) {
      final full = normalizeName(p.name);
      byFull[full] = byFull.containsKey(full) ? null : p;
      final first = full.split(' ').first;
      byFirst[first] = byFirst.containsKey(first) ? null : p;
    }

    Person? lookup(String raw) {
      final key = normalizeName(
        raw.replaceAll(RegExp('[~\\u200e\\u202a\\u202c]'), ''),
      );
      if (key.isEmpty) return null;
      return byFull[key] ?? byFirst[key];
    }

    // Satırları gönderene göre mesajlara ayır.
    final messages = <(String, StringBuffer)>[];
    final unmatched = <String>[];
    for (final rawLine in text.split(RegExp(r'\r?\n'))) {
      final line = rawLine.replaceAll('\u200e', '').trimRight();
      if (line.trim().isEmpty) continue;
      var rest = line;
      final hadPrefix =
          _bracketPrefix.hasMatch(rest) || _dashPrefix.hasMatch(rest);
      rest = rest
          .replaceFirst(_bracketPrefix, '')
          .replaceFirst(_dashPrefix, '');
      Person? sender;
      String body = rest;
      final colon = rest.indexOf(':');
      if (colon > 0 && colon < 40) {
        sender = lookup(rest.substring(0, colon));
        if (sender != null) body = rest.substring(colon + 1);
      }
      if (sender == null) {
        // "Emre Dinç 3 5" ya da "Emre 3 5": satır başındaki ad.
        final norm = normalizeName(rest);
        final words = norm.split(' ');
        for (var n = words.length; n >= 1 && sender == null; n--) {
          final candidate = words.take(n).join(' ');
          final p = byFull[candidate] ?? (n == 1 ? byFirst[candidate] : null);
          if (p != null) {
            sender = p;
            body = words.skip(n).join(' ');
          }
        }
      }
      // "Ad: …" biçiminde ama ad tanınmadı: başkasının mesajına eklenmesin.
      final looksLikeSender =
          colon > 0 &&
          colon < 40 &&
          RegExp(r'^[^\d,;]+$').hasMatch(rest.substring(0, colon));
      if (sender != null) {
        messages.add((sender.id, StringBuffer(body)));
      } else if (messages.isNotEmpty && !hadPrefix && !looksLikeSender) {
        messages.last.$2.write('\n$rest');
      } else {
        unmatched.add(line.trim());
      }
    }

    final requests = <String, PersonRequest>{};
    final replied = <String>{};
    final warnings = <String>[];
    String name(String id) => people.firstWhere((p) => p.id == id).name;
    for (final (id, body) in messages) {
      replied.add(id);
      final (request, skipped) = _parseBody(
        body.toString(),
        month: month,
        daysInMonth: daysInMonth,
      );
      if (skipped.isNotEmpty) {
        warnings.add(
          '${name(id)}: ${skipped.join(', ')} ayın günü değil, atlandı.',
        );
      }
      if (request.isEmpty) continue;
      requests[id] = requests[id]?.merge(request) ?? request;
    }
    return RequestParseResult(
      requests: requests,
      replied: replied,
      unmatched: unmatched,
      warnings: warnings,
    );
  }

  static final _monthWords = [
    for (final m in turkishMonthNames) turkishLowerCase(m),
  ];

  /// Mesaj gövdesini okur; (istekler, ayda olmayan sayılar).
  static (PersonRequest, List<int>) _parseBody(
    String body, {
    required int month,
    required int daysInMonth,
  }) {
    var text = turkishLowerCase(body);
    // Saatler ve başka aya ait tarihler günden sayılmasın.
    text = text.replaceAll(RegExp(r'\b\d{1,2}:\d{2}\b'), ' ');
    text = text.replaceAllMapped(
      RegExp(r'\b(\d{1,2})[./](\d{1,2})(?:[./]\d{2,4})?\b'),
      (m) => int.parse(m[2]!) == month ? m[1]! : ' ',
    );

    final overtime =
        text.contains('fazla mesai') &&
        !RegExp(r'fazla mesai\s+(istemiyorum|yok|istemem)').hasMatch(text);
    // "fazla mesai 5 gün" gibi sayılar gün sayılmasın.
    text = text.replaceAll(RegExp(r'fazla mesai[^,\n;.]*'), ' ');

    final unavailable = <int>{};
    final leaves = <LeaveType, Set<int>>{};
    final skipped = <int>[];

    // Belirteçler: sayı aralığı, sayı, sözcük, virgül grubu sonu.
    final token = RegExp(
      r"(?<!\d)(\d{1,2})(?:'?[a-zçğıöşü]*\s*(?:-|–|ile|ila)|'?(?:dan|den|tan|ten))"
      r"\s*(\d{1,2})(?!\d)"
      r'|(?<!\d)(\d{1,2})(?!\d)'
      r'|([a-zçğıöşü]+(?:\s+değil)?)'
      r'|([,;\n.])',
    );
    final suffixPattern = RegExp(r"^'?\s*([a-zçğıöşü]+)");
    var mode = 'unavailable'; // ya da LeaveType.name
    // Son virgül grubundaki günler: "olmaz" geriye dönük uygulansın.
    var group = <int>[];
    final assigned = <int, String>{};

    void put(int d) {
      if (d < 1 || d > daysInMonth) {
        skipped.add(d);
        return;
      }
      assigned[d] = mode;
      group.add(d);
    }

    for (final m in token.allMatches(text)) {
      if (m[1] != null) {
        final a = int.parse(m[1]!), b = int.parse(m[2]!);
        final lo = a < b ? a : b, hi = a < b ? b : a;
        for (var d = lo; d <= hi; d++) {
          put(d);
        }
      } else if (m[3] != null) {
        final suffix =
            suffixPattern.firstMatch(text.substring(m.end))?[1] ?? '';
        // "12 aralık": başka ayın adı geçiyorsa atla.
        final monthIndex = _monthWords.indexWhere(suffix.startsWith);
        if (monthIndex >= 0 && monthIndex + 1 != month) continue;
        // "3 gün", "2 hafta" gibi süreler gün değil.
        if (suffix.startsWith('gün') || suffix.startsWith('hafta')) continue;
        put(int.parse(m[3]!));
      } else if (m[4] != null) {
        final word = m[4]!;
        final leave = _leaveWords.entries
            .where((e) => word.startsWith(e.key))
            .map((e) => e.value)
            .firstOrNull;
        if (leave != null) {
          mode = leave.name;
          group = [];
        } else if (_unavailableWords.any(word.startsWith)) {
          for (final d in group) {
            assigned[d] = 'unavailable';
          }
          mode = 'unavailable';
          group = [];
        }
      } else if (m[5] != null) {
        group = [];
        if (m[5] == '\n' || m[5] == '.') mode = 'unavailable';
      }
    }
    for (final MapEntry(key: d, value: kind) in assigned.entries) {
      if (kind == 'unavailable') {
        unavailable.add(d);
      } else {
        (leaves[LeaveType.values.byName(kind)] ??= {}).add(d);
      }
    }
    return (
      PersonRequest(
        unavailable: unavailable,
        leaves: leaves,
        overtime: overtime,
      ),
      skipped,
    );
  }
}
