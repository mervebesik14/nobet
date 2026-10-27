import '../models/models.dart';
import 'turkish_collation.dart';
import 'turkish_dates.dart';

/// Dosyadan liste okunamadı (ör. gün başlıkları yok).
class RosterImportException implements Exception {
  const RosterImportException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Dışarıda hazırlanmış listenin okunmuş hâli.
class RosterImportResult {
  const RosterImportResult({
    required this.assignments,
    required this.leaves,
    required this.shiftCount,
    required this.matchedPeople,
    required this.hasTechShifts,
    required this.warnings,
    this.techDayShifts = const {},
  });

  /// Ayın her günü (boş günler dahil) → nöbetçiler.
  final Map<int, DayAssignment> assignments;

  /// Dosyada işaretli izinler: tür → kişi → günler.
  final Map<LeaveType, Map<String, List<int>>> leaves;

  /// Okunan nöbet hücresi sayısı.
  final int shiftCount;

  /// Nöbeti ya da izni okunan kişiler.
  final Set<String> matchedPeople;

  /// En az bir teknikere nöbet yazılmış mı? (yoksa yalnız hemşire listesi)
  final bool hasTechShifts;

  /// Okurken atlanan / anlaşılamayan şeyler, kullanıcıya gösterilir.
  final List<String> warnings;

  /// Teknikerlerin 7A günleri: kişi → günler.
  final Map<String, List<int>> techDayShifts;

  int get leaveDayCount => leaves.values.fold(
    0,
    (s, byPerson) => s + byPerson.values.fold(0, (a, d) => a + d.length),
  );
}

/// Tablo hâlindeki listeyi (Excel'den okunan hücreler) ay listesine çevirir
/// (saf Dart). Biçim, uygulamanın paylaştığı "Nöbet Listesi" sayfasıyla
/// aynıdır; böylece paylaşılan liste Excel'de düzenlenip geri alınabilir:
///
/// - Bir satırda gün başlıkları (1, 2, 3, … ; "1\nPer" gibi gün adı ekli
///   olabilir), hemen solundaki sütunda kişi adları.
/// - Hücreler: `24`, `X`, `✓`, `N`, `Nöbet` → nöbet; `16B` → günde iki
///   tekniker varken 16B vardiyası; `Y.İ.` / `Ş.İ.` / `R.` (ya da `Yıllık`,
///   `Şua`, `Rapor`) → izin; `7A` teknikerde 7A günü, hemşirede yok
///   sayılır (sorumlu hemşire planından otomatik hesaplanır).
/// - İsimler Türkçe büyük/küçük harf ve fazla boşluk gözetmeden eşlenir;
///   grup başlıkları ("Hemşireler") ve açıklama satırları kendiliğinden
///   atlanır.
class RosterImport {
  const RosterImport._();

  static final _dayHeader = RegExp(r'^\s*(\d{1,2})(?!\d)');

  static int? _headerDay(Object? v) {
    if (v is num) return v == v.roundToDouble() ? v.round() : null;
    if (v is String) {
      final m = _dayHeader.firstMatch(v);
      return m == null ? null : int.parse(m[1]!);
    }
    return null;
  }

  /// Hücre metninin karşılaştırma için sade hâli: büyük harf, nokta ve
  /// boşluk yok ("y.i." → "YI", "Ş.İ." → "ŞI").
  static String _code(Object? v) {
    final text = v is num
        ? (v == v.roundToDouble() ? '${v.round()}' : '$v')
        : '${v ?? ''}';
    return turkishLowerCase(text)
        .replaceAll(RegExp(r'[\s.]'), '')
        .replaceAll('i', 'ı')
        .replaceAll('ı', 'I')
        .toUpperCase();
  }

  static const _leaveCodes = {
    'YI': LeaveType.annual,
    'YILLIK': LeaveType.annual,
    'YILLIKIZIN': LeaveType.annual,
    'IZIN': LeaveType.annual,
    'ŞI': LeaveType.radiation,
    'ŞUA': LeaveType.radiation,
    'ŞUAIZNI': LeaveType.radiation,
    'R': LeaveType.sick,
    'RAPOR': LeaveType.sick,
  };

  static const _shiftCodes = {'24', 'X', '✓', '✔', 'N', 'NÖBET', '+'};

  /// Kişi olmayan, sessizce atlanan satırlar: grup başlıkları ve dışa
  /// aktarılan listedeki "Eksik" satırı.
  static final _skippedRows = {
    for (final role in Role.values) normalizeName(role.pluralLabel),
    normalizeName('Eksik'),
    normalizeName('Ad Soyad'),
  };

  static RosterImportResult fromRows({
    required List<List<Object?>> rows,
    required int year,
    required int month,
    required Iterable<Person> people,
    int techsPerDay = 1,
    int shiftHours = 24,
  }) {
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final warnings = <String>[];

    // Gün başlığı satırı: 1'den başlayıp art arda artan en uzun dizi.
    var headerRow = -1;
    var firstCol = -1;
    var dayCount = 0;
    for (var r = 0; r < rows.length; r++) {
      final row = rows[r];
      for (var c = 0; c < row.length; c++) {
        if (_headerDay(row[c]) != 1) continue;
        var n = 1;
        while (c + n < row.length && _headerDay(row[c + n]) == n + 1) {
          n++;
        }
        if (n > dayCount) {
          headerRow = r;
          firstCol = c;
          dayCount = n;
        }
      }
    }
    if (dayCount < 7 || firstCol < 1) {
      throw const RosterImportException(
        'Gün başlıkları (1, 2, 3, …) ve solunda isim sütunu bulunamadı. '
        'Uygulamanın verdiği şablonu kullanın.',
      );
    }
    if (dayCount != daysInMonth) {
      warnings.add(
        'Dosyada $dayCount gün var; ${turkishMonthNames[month - 1]} '
        '$daysInMonth gün. '
        '${dayCount > daysInMonth ? 'Fazla günler atlandı.' : 'Eksik günler boş kaldı.'}',
      );
    }
    final nameCol = firstCol - 1;
    final days = dayCount < daysInMonth ? dayCount : daysInMonth;

    // İsim → kişi (aynı adı taşıyan birden çok kişi varsa eşlenmez).
    final byName = <String, Person?>{};
    for (final p in people) {
      final key = normalizeName(p.name);
      byName[key] = byName.containsKey(key) ? null : p;
    }

    final nurses = {for (var d = 1; d <= days; d++) d: <String>[]};
    final tech24 = {for (var d = 1; d <= days; d++) d: <String>[]};
    final tech16 = {for (var d = 1; d <= days; d++) d: <String>[]};
    final leaves = <LeaveType, Map<String, List<int>>>{};
    final techDayShifts = <String, List<int>>{};
    final matched = <String>{};
    final unknownValues = <String, int>{};
    final seenRows = <String>{};
    var shiftCount = 0;

    for (var r = headerRow + 1; r < rows.length; r++) {
      final row = rows[r];
      final rawName = nameCol < row.length ? row[nameCol] : null;
      if (rawName is! String || rawName.trim().isEmpty) continue;
      final key = normalizeName(rawName);
      final cells = [
        for (var d = 1; d <= days; d++)
          firstCol + d - 1 < row.length ? row[firstCol + d - 1] : null,
      ];
      final marks = cells.where((v) => _code(v).isNotEmpty).length;
      final person = byName[key];
      if (person == null) {
        if (marks > 0 && byName.containsKey(key)) {
          warnings.add(
            '"${rawName.trim()}" adında birden çok kişi var; satırı atlandı.',
          );
        } else if (marks > 0 && !_skippedRows.contains(key)) {
          warnings.add(
            '"${rawName.trim()}" kişiler arasında yok; satırı atlandı '
            '($marks dolu hücre).',
          );
        }
        continue;
      }
      if (!seenRows.add(person.id)) {
        warnings.add('${person.name} iki satırda var; ikincisi atlandı.');
        continue;
      }
      for (var d = 1; d <= days; d++) {
        final code = _code(cells[d - 1]);
        if (code.isEmpty) continue;
        if (code == '7A') {
          if (person.role == Role.radiologyTech) {
            (techDayShifts[person.id] ??= []).add(d);
            matched.add(person.id);
          }
          continue;
        }
        if (_leaveCodes[code] case final type?) {
          ((leaves[type] ??= {})[person.id] ??= []).add(d);
          matched.add(person.id);
          continue;
        }
        final is16 = code == '16B' || code == '16';
        if (!is16 && !_shiftCodes.contains(code) && code != '$shiftHours') {
          final shown = '${cells[d - 1]}'.trim();
          unknownValues[shown] = (unknownValues[shown] ?? 0) + 1;
          continue;
        }
        matched.add(person.id);
        shiftCount++;
        if (person.role == Role.nurse) {
          nurses[d]!.add(person.id);
        } else if (is16 && techsPerDay >= 2) {
          tech16[d]!.add(person.id);
        } else {
          tech24[d]!.add(person.id);
        }
      }
    }

    if (unknownValues.isNotEmpty) {
      final total = unknownValues.values.fold(0, (a, b) => a + b);
      final sample = unknownValues.keys.take(3).map((v) => '"$v"').join(', ');
      warnings.add('$total hücre anlaşılamadı ve atlandı (ör. $sample).');
    }

    String name(String id) => people.firstWhere((p) => p.id == id).name;
    final assignments = <int, DayAssignment>{};
    for (var d = 1; d <= daysInMonth; d++) {
      final t24 = tech24[d] ?? const <String>[];
      final t16 = tech16[d] ?? const <String>[];
      if (t24.length > 1) {
        warnings.add(
          '${formatDayMonth(d, month)}: birden çok tekniker 24 nöbette; '
          'yalnız ${name(t24.first)} alındı.',
        );
      }
      if (t16.length > 1) {
        warnings.add(
          '${formatDayMonth(d, month)}: birden çok tekniker 16B\'de; '
          'yalnız ${name(t16.first)} alındı.',
        );
      }
      assignments[d] = DayAssignment(
        day: d,
        nurseIds: [...?nurses[d]],
        techId: t24.firstOrNull,
        tech16bId: t16.firstOrNull,
      );
    }

    return RosterImportResult(
      assignments: assignments,
      leaves: leaves,
      shiftCount: shiftCount,
      matchedPeople: matched,
      hasTechShifts: assignments.values.any(
        (a) => a.techId != null || a.tech16bId != null,
      ),
      warnings: warnings,
      techDayShifts: techDayShifts,
    );
  }
}
