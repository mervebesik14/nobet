import 'dart:math';

import '../models/day_assignment.dart';
import '../models/holiday.dart';
import '../models/person.dart';
import '../models/role.dart';
import '../models/roster_settings.dart';
import 'turkish_collation.dart';
import 'turkish_dates.dart';

/// Listenin kurulamadığı bir gün ve nedeni.
class RosterIssue {
  const RosterIssue({
    required this.day,
    required this.role,
    required this.missing,
    required this.message,
  });

  final int day;
  final Role role;

  /// O gün o rolde boş kalan koltuk sayısı.
  final int missing;

  /// Türkçe açıklama, ör. "18 Ekim: 1 radyoloji teknikeri eksik. Ali
  /// istemiyor; Can 17 Ekim'de nöbetçi (art arda gün)."
  final String message;

  @override
  String toString() => message;
}

/// [RosterGenerator] sonucu.
class RosterResult {
  const RosterResult({
    required this.assignments,
    required this.score,
    required this.issues,
    required this.seed,
  });

  /// Ayın günü → nöbetçiler. Liste tam kurulamadıysa bazı günlerde eksik
  /// kişi olabilir; eksikler [issues] içinde açıklanır.
  final Map<int, DayAssignment> assignments;

  /// Adalet puanı (düşük daha iyi): rol grubu içinde toplam nöbet, hafta
  /// sonu nöbeti ve gün aşırı çift sayısı sapmalarının kareleri toplamı ve
  /// toplam gün aşırı çift sayısı için küçük bir ceza. Boş koltuk başına
  /// [RosterGenerator.emptySlotPenalty] eklenir.
  final double score;

  final List<RosterIssue> issues;

  /// Bu sonucu üreten tohum; aynı girdiler ve tohumla aynı liste çıkar.
  final int seed;

  /// Tüm koltuklar dolu mu?
  bool get isComplete => issues.isEmpty;
}

/// Bir kişinin bir güne atanamama nedeni.
enum _Block { unavailable, sameDay, consecutive, chain, cap }

/// Nöbet dağıtım algoritması (saf Dart).
///
/// Roller birbirinden bağımsızdır (kurallar kişi başına, koltuklar rol
/// başına), bu yüzden her rol ayrı çözülür. Her rol için:
/// 1. Günler zordan kolaya (uygun kişi az olan, hafta sonu önce) ya da
///    takvim sırasıyla dolaşılır; her koltuğa sert kuralları geçen adaylar
///    arasından ceza puanı en düşük olan atanır (eşitlikte tohumlu rastgele).
/// 2. Bu [attempts] kez farklı rastgelelikle denenir.
/// 3. En iyi birkaç deneme, yerel iyileştirme ile geliştirilir: boş koltuğu
///    doldurma, bir günün nöbetçisini başkasıyla değiştirme, iki kişinin iki
///    günlük nöbetini takas etme. Puanı düşüren hamle kalmayana kadar sürer.
///
/// Sert kurallar asla çiğnenmez; bir koltuk dolamazsa boş bırakılır ve
/// [RosterResult.issues] içinde nedeniyle raporlanır.
class RosterGenerator {
  RosterGenerator({
    required this.year,
    required this.month,
    required Iterable<Person> people,
    this.unavailableDays = const {},
    this.holidays = const [],
    this.settings = const RosterSettings(),
    this.seed = 0,
    this.previousMonthTail = const [],
    this.attempts = 400,
  }) : people = people.where((p) => p.isActive).toList()
         ..sort((a, b) => a.id.compareTo(b.id));

  final int year;
  final int month;

  /// Aktif kişiler (pasifler atılır), kimliğe göre sıralı (belirlenimcilik).
  final List<Person> people;

  /// Kişi kimliği → nöbet istemediği günler.
  final Map<String, List<int>> unavailableDays;
  final List<Holiday> holidays;
  final RosterSettings settings;
  final int seed;

  /// Önceki ayın son günlerinin nöbetçileri, eskiden yeniye; son eleman
  /// önceki ayın son günüdür. Art arda gün ve gün aşırı zincir kuralları
  /// ay sınırında da uygulanır.
  final List<Set<String>> previousMonthTail;

  /// Rol başına açgözlü deneme sayısı.
  final int attempts;

  /// Boş kalan her koltuk için puana eklenen ceza.
  static const emptySlotPenalty = 1000.0;

  /// Yerel iyileştirmeye alınan en iyi deneme sayısı.
  static const _polishCount = 3;

  int get daysInMonth => DateTime(year, month + 1, 0).day;

  /// Hafta sonu sayılan günler: Cumartesi, Pazar ve
  /// [RosterSettings.holidayCountsAsWeekend] açıksa tam gün resmi tatiller
  /// (yarım gün arifeler hafta içi sayılır).
  static Set<int> weekendDays(
    int year,
    int month,
    Iterable<Holiday> holidays,
    RosterSettings settings,
  ) {
    final days = DateTime(year, month + 1, 0).day;
    return {
      for (var d = 1; d <= days; d++)
        if (DateTime(year, month, d).weekday >= DateTime.saturday) d,
      if (settings.holidayCountsAsWeekend)
        for (final h in holidays)
          if (!h.isHalfDay && h.date.year == year && h.date.month == month)
            h.date.day,
    };
  }

  /// Gün aşırı çift sayısı: kişinin hem d hem d+2 günü nöbetçi olduğu d'ler.
  static int everyOtherDayPairs(Set<int> days) =>
      days.where((d) => days.contains(d + 2)).length;

  RosterResult generate() {
    final rng = Random(seed);
    final weekend = weekendDays(year, month, holidays, settings);
    final perRole = <Role, _RoleSolution>{};

    for (final role in Role.values) {
      final perDay = switch (role) {
        Role.nurse => settings.nursesPerDay,
        Role.radiologyTech => settings.techsPerDay,
      };
      final members = people.where((p) => p.role == role).toList();
      final solver = _RoleSolver(
        role: role,
        members: members,
        perDay: perDay,
        days: daysInMonth,
        available: {
          for (final p in members)
            p.id: {
              for (var d = 1; d <= daysInMonth; d++)
                if (!(unavailableDays[p.id] ?? const []).contains(d)) d,
            },
        },
        weekend: weekend,
        tail: _tailFor(members),
        settings: settings,
      );
      perRole[role] = solver.solve(rng, attempts, _polishCount);
    }

    final nurses = perRole[Role.nurse]!;
    final techs = perRole[Role.radiologyTech]!;
    final assignments = {
      for (var d = 1; d <= daysInMonth; d++)
        d: DayAssignment(
          day: d,
          nurseIds: [...nurses.slots[d]],
          techId: techs.slots[d].firstOrNull,
        ),
    };
    final issues = [
      for (final role in Role.values) ...perRole[role]!.issues(month),
    ]..sort((a, b) => a.day.compareTo(b.day));

    return RosterResult(
      assignments: assignments,
      score: nurses.score + techs.score,
      issues: issues,
      seed: seed,
    );
  }

  /// Kişi → önceki ayda nöbet tuttuğu günler (0 = önceki ayın son günü,
  /// -1 = ondan önceki gün, ...).
  Map<String, Set<int>> _tailFor(List<Person> members) {
    final ids = {for (final p in members) p.id};
    final result = <String, Set<int>>{};
    for (var i = 0; i < previousMonthTail.length; i++) {
      final offset = i - (previousMonthTail.length - 1);
      for (final id in previousMonthTail[i]) {
        if (ids.contains(id)) (result[id] ??= {}).add(offset);
      }
    }
    return result;
  }
}

/// Bir rolün çözümü: gün → nöbetçiler.
class _RoleSolution {
  _RoleSolution(this.solver, this.slots, this.score);

  final _RoleSolver solver;
  final List<List<String>> slots;
  final double score;

  Iterable<RosterIssue> issues(int month) sync* {
    for (var d = 1; d < slots.length; d++) {
      final missing = solver.perDay - slots[d].length;
      if (missing > 0) yield solver.describeGap(d, missing, month);
    }
  }
}

/// Tek bir rolün dağıtımı. Durum: [_slots] (gün → kişiler) ve [_worked]
/// (kişi → günler); ikisi hep birlikte güncellenir.
class _RoleSolver {
  _RoleSolver({
    required this.role,
    required this.members,
    required this.perDay,
    required this.days,
    required this.available,
    required this.weekend,
    required this.tail,
    required RosterSettings settings,
  }) : forbidConsecutive = settings.forbidConsecutiveDays,
       maxChain = max(1, settings.maxEveryOtherDayChain),
       ids = [for (final p in members) p.id],
       cap = settings.maxExtraOverAverage == null || members.isEmpty
           ? null
           : (days * perDay / members.length).ceil() +
                 settings.maxExtraOverAverage!;

  final Role role;
  final List<Person> members;
  final List<String> ids;
  final int perDay;
  final int days;
  final Map<String, Set<int>> available;
  final Set<int> weekend;
  final Map<String, Set<int>> tail;
  final bool forbidConsecutive;
  final int maxChain;
  final int? cap;

  late List<List<String>> _slots;
  late Map<String, Set<int>> _worked;

  int get _totalSlots => days * perDay;

  void _reset() {
    _slots = List.generate(days + 1, (_) => <String>[]);
    _worked = {for (final id in ids) id: <int>{}};
  }

  void _load(List<List<String>> slots) {
    _reset();
    for (var d = 1; d <= days; d++) {
      for (final id in slots[d]) {
        _add(id, d);
      }
    }
  }

  List<List<String>> _snapshot() => [
    for (final s in _slots) [...s],
  ];

  void _add(String id, int d) {
    _slots[d].add(id);
    _worked[id]!.add(d);
  }

  void _remove(String id, int d) {
    _slots[d].remove(id);
    _worked[id]!.remove(d);
  }

  bool _works(String id, int d) {
    if (d <= 0) return tail[id]?.contains(d) ?? false;
    return _worked[id]!.contains(d);
  }

  /// [id] kişisi [d] gününe eklenebilir mi? Eklenemezse ilk engel.
  _Block? _block(String id, int d) {
    if (!available[id]!.contains(d)) return _Block.unavailable;
    if (_worked[id]!.contains(d)) return _Block.sameDay;
    if (forbidConsecutive && (_works(id, d - 1) || _works(id, d + 1))) {
      return _Block.consecutive;
    }
    if (_breaksChain(id, d)) return _Block.chain;
    if (cap != null && _worked[id]!.length >= cap!) return _Block.cap;
    return null;
  }

  /// [d] eklenince d, d±2, ... dizisinde [maxChain]'den uzun zincir oluşur mu?
  bool _breaksChain(String id, int d) {
    for (var j = 0; j <= maxChain; j++) {
      final start = d - 2 * j;
      var full = true;
      for (var k = 0; k <= maxChain && full; k++) {
        final day = start + 2 * k;
        if (day != d && !_works(id, day)) full = false;
      }
      if (full) return true;
    }
    return false;
  }

  int _weekendCount(String id) => _worked[id]!.where(weekend.contains).length;

  int _pairs(String id) => RosterGenerator.everyOtherDayPairs(_worked[id]!);

  /// Rol puanı: grup içi sapmaların kareleri + toplam çift cezası + boş
  /// koltuk cezası.
  double _score() {
    if (ids.isEmpty) return _emptySlots() * RosterGenerator.emptySlotPenalty;
    final n = ids.length;
    final counts = [for (final id in ids) _worked[id]!.length];
    final weekends = [for (final id in ids) _weekendCount(id)];
    final pairs = [for (final id in ids) _pairs(id)];

    double sq(List<int> values) {
      final mean = values.fold(0, (a, b) => a + b) / n;
      return values.fold(0.0, (s, v) => s + (v - mean) * (v - mean));
    }

    final totalPairs = pairs.fold(0, (a, b) => a + b);
    return sq(counts) +
        sq(weekends) +
        sq(pairs) +
        0.25 * totalPairs +
        _emptySlots() * RosterGenerator.emptySlotPenalty;
  }

  int _emptySlots() {
    var empty = 0;
    for (var d = 1; d <= days; d++) {
      empty += perDay - _slots[d].length;
    }
    return empty;
  }

  _RoleSolution solve(Random rng, int attempts, int polishCount) {
    _reset();
    if (perDay <= 0) return _RoleSolution(this, _snapshot(), 0);

    final candidates = <(double, List<List<String>>)>[];
    for (var i = 0; i < max(1, attempts); i++) {
      _greedy(rng, chronological: i % 4 == 3);
      candidates.add((_score(), _snapshot()));
    }
    candidates.sort((a, b) => a.$1.compareTo(b.$1));

    var best = candidates.first;
    for (final (_, slots) in candidates.take(polishCount)) {
      _load(slots);
      _improve(rng);
      final score = _score();
      if (score < best.$1) best = (score, _snapshot());
    }
    _load(best.$2);
    return _RoleSolution(this, best.$2, best.$1);
  }

  void _greedy(Random rng, {required bool chronological}) {
    _reset();
    final order = [for (var d = 1; d <= days; d++) d];
    if (!chronological) {
      final availableCount = {
        for (final d in order)
          d: ids.where((id) => available[id]!.contains(d)).length,
      };
      final tieBreak = {for (final d in order) d: rng.nextDouble()};
      order.sort((a, b) {
        final c = availableCount[a]!.compareTo(availableCount[b]!);
        if (c != 0) return c;
        final w = (weekend.contains(b) ? 1 : 0).compareTo(
          weekend.contains(a) ? 1 : 0,
        );
        if (w != 0) return w;
        return tieBreak[a]!.compareTo(tieBreak[b]!);
      });
    }

    for (final d in order) {
      for (var slot = 0; slot < perDay; slot++) {
        String? bestId;
        var bestCost = double.infinity;
        for (final id in ids) {
          if (_block(id, d) != null) continue;
          final cost = _cost(id, d) + rng.nextDouble() * 2;
          if (cost < bestCost) {
            bestCost = cost;
            bestId = id;
          }
        }
        if (bestId == null) break;
        _add(bestId, d);
      }
    }
  }

  /// Açgözlü adımda [id] kişisini [d] gününe atamanın ceza puanı.
  double _cost(String id, int d) {
    final n = ids.length;
    var cost = (_worked[id]!.length + 1 - _totalSlots / n) * 10;
    if (weekend.contains(d)) {
      cost += (_weekendCount(id) + 1 - weekend.length * perDay / n) * 10;
    }
    final newPairs =
        (d - 2 >= 1 && _works(id, d - 2) ? 1 : 0) + (_works(id, d + 2) ? 1 : 0);
    if (newPairs > 0) {
      final meanPairs = ids.map(_pairs).fold(0, (a, b) => a + b) / n;
      cost += newPairs * ((_pairs(id) + 1 - meanPairs) * 10 + 3);
    }
    // Nöbetler aralıklı dağılsın: 3 gün arayla nöbete küçük ceza.
    if (_works(id, d - 3) || _works(id, d + 3)) cost += 1;
    return cost;
  }

  /// Yerel iyileştirme: puanı düşüren hamle kalmayana kadar.
  void _improve(Random rng) {
    var current = _score();
    for (var pass = 0; pass < 30; pass++) {
      var improved = false;

      // Boş koltukları doldur.
      for (var d = 1; d <= days; d++) {
        for (final id in [...ids]..shuffle(rng)) {
          if (_slots[d].length >= perDay) break;
          if (_block(id, d) == null) {
            _add(id, d);
            improved = true;
          }
        }
      }
      if (improved) current = _score();

      // Değiştirme: d günündeki a yerine b.
      for (var d = 1; d <= days; d++) {
        for (final a in [..._slots[d]]) {
          for (final b in ids) {
            if (_slots[d].contains(b)) continue;
            _remove(a, d);
            if (_block(b, d) == null) {
              _add(b, d);
              final score = _score();
              if (score < current - 1e-9) {
                current = score;
                improved = true;
                break;
              }
              _remove(b, d);
            }
            _add(a, d);
          }
        }
      }

      // Takas: a@d1 ↔ b@d2.
      final shifts = [
        for (var d = 1; d <= days; d++)
          for (final id in _slots[d]) (d, id),
      ];
      for (var i = 0; i < shifts.length; i++) {
        for (var j = i + 1; j < shifts.length; j++) {
          final (d1, a) = shifts[i];
          final (d2, b) = shifts[j];
          if (a == b || d1 == d2) continue;
          if (!_slots[d1].contains(a) || !_slots[d2].contains(b)) continue;
          if (_slots[d1].contains(b) || _slots[d2].contains(a)) continue;
          if (_trySwap(a, d1, b, d2, current)) {
            current = _score();
            improved = true;
            shifts[i] = (d1, b);
            shifts[j] = (d2, a);
          }
        }
      }

      if (!improved) break;
    }
  }

  /// a@d1 ve b@d2'yi takas eder; kurallar geçerli ve puan düşüyorsa
  /// kalıcı yapar ve true döner, yoksa geri alır.
  bool _trySwap(String a, int d1, String b, int d2, double current) {
    _remove(a, d1);
    _remove(b, d2);
    if (_block(b, d1) == null) {
      _add(b, d1);
      if (_block(a, d2) == null) {
        _add(a, d2);
        if (_score() < current - 1e-9) return true;
        _remove(a, d2);
      }
      _remove(b, d1);
    }
    _add(a, d1);
    _add(b, d2);
    return false;
  }

  /// Boş koltuğun nedenini kişi kişi açıklar.
  RosterIssue describeGap(int d, int missing, int month) {
    final label = turkishLowerCase(role.label);
    if (members.isEmpty) {
      return RosterIssue(
        day: d,
        role: role,
        missing: missing,
        message:
            '${formatDayMonth(d, month)}: $missing $label eksik. '
            'Hiç aktif ${turkishLowerCase(role.label)} yok.',
      );
    }
    String date(int day) => day >= 1
        ? formatDayMonth(day, month)
        : 'önceki ayın ${day == 0 ? 'son günü' : '${1 - day}. son günü'}';
    final reasons = <String>[];
    for (final p in [
      ...members,
    ]..sort((a, b) => compareTurkish(a.name, b.name))) {
      if (_slots[d].contains(p.id)) continue;
      final reason = switch (_block(p.id, d)) {
        _Block.unavailable => 'istemiyor',
        _Block.sameDay || null => null,
        _Block.consecutive =>
          '${date(_works(p.id, d - 1) ? d - 1 : d + 1)} nöbetçi (art arda gün)',
        _Block.chain => 'gün aşırı zincir sınırında',
        _Block.cap => 'nöbet sınırına ulaştı',
      };
      if (reason != null) reasons.add('${p.name} $reason');
    }
    return RosterIssue(
      day: d,
      role: role,
      missing: missing,
      message:
          '${formatDayMonth(d, month)}: $missing $label eksik. '
          '${reasons.join('; ')}.',
    );
  }
}
