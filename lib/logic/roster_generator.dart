import 'dart:math';

import '../models/day_assignment.dart';
import '../models/holiday.dart';
import '../models/person.dart';
import '../models/role.dart';
import '../models/roster_settings.dart';
import 'person_totals.dart';
import 'shift_gaps.dart';
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
    this.yearToDate = const {},
    this.overtimeRequests = const {},
    this.overtimeAllowance = 2,
    this.requestedShifts = const {},
    this.absentDays = const {},
    this.existing,
    this.attempts = 400,
  }) : people = people.where((p) => p.worksInMonth(year, month)).toList()
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

  /// Kişi → bu yıl önceki aylarda biriken toplamlar. Ay içinde nöbetler
  /// tam bölünmüyorsa (ör. 62 / 7 = 8,86) fazla nöbet yıl içi toplamı en
  /// düşük olanlara gider; hafta sonu ve gün aşırı çift için de aynısı.
  /// Ay içi denge (fark ≤ 1) yine önceliklidir.
  final Map<String, PersonTotals> yearToDate;

  /// Bu ay fazla mesai isteyen kişiler; nöbet sayıları [overtimeAllowance]
  /// kadar diğerlerinin üstüne çıkabilir.
  final Set<String> overtimeRequests;

  /// Fazla mesai isteyene tanınan ek nöbet payı.
  final int overtimeAllowance;

  /// Kişi → mutlaka nöbet tutacağı günler: sorumlu hemşirenin seçtiği
  /// günler ve şua izni dönüşünün ilk iş günü. Bu günlere sabit yazılır;
  /// kalan koltuklar diğerleriyle dolar. Kişinin o gün uygun olmadığı
  /// (istemediği / izinli) günler yok sayılır.
  final Map<String, List<int>> requestedShifts;

  /// Kişi → izinli (yıllık / şua / rapor) günler. Araya izin giren
  /// nöbetler arası boşluk, boşluk sınırına ve dengesine sayılmaz. Pasif
  /// günler kişiden ayrıca eklenir.
  final Map<String, List<int>> absentDays;

  /// Düzeltme modu: verilirse liste baştan kurulmaz, bu atamalardan
  /// başlanır. Kural bozan nöbetler (istemediği / izinli gün, art arda,
  /// zincir…) çıkarılır, boşalan koltuklar doldurulur ve boşluk / adalet
  /// kuralları en az değişiklikle düzeltilir ([changePenalty]).
  final Map<int, DayAssignment>? existing;

  Map<String, Set<int>> _absentFor(List<Person> members) => {
    for (final p in members)
      p.id: {...?absentDays[p.id], ...p.inactiveDaysIn(year, month)},
  };

  /// Kişi → mutlaka nöbet tutacağı günler ([requestedShifts]); ayın dışı ve
  /// istemediği / izinli günler atılır.
  Map<String, Set<int>> _fixedFor(List<Person> members) => {
    for (final p in members)
      if (requestedShifts[p.id]?.isNotEmpty ?? false)
        p.id: {
          for (final d in requestedShifts[p.id]!)
            if (d >= 1 &&
                d <= daysInMonth &&
                !(unavailableDays[p.id] ?? const []).contains(d))
              d,
        },
  };

  /// Kişi → fazla mesai payı (fazla mesai isteyene [overtimeAllowance], yoksa
  /// 0). Adalet puanında ve açgözlü seçimde kişinin sayısından düşülür.
  Map<String, int> _allowanceFor(List<Person> members) => {
    for (final p in members)
      p.id: overtimeRequests.contains(p.id) ? overtimeAllowance : 0,
  };

  /// Rol başına açgözlü deneme sayısı.
  final int attempts;

  /// Boş kalan her koltuk için puana eklenen ceza.
  static const emptySlotPenalty = 1000.0;

  /// Düzeltme modunda mevcut listeden her farklı atama için ceza: kural
  /// cezalarından küçük, küçük denge iyileştirmelerinden büyük; liste
  /// yalnız bir kuralı düzeltmek için değişir.
  static const changePenalty = 8.0;

  /// Ay içinde bir dengenin (toplam, hafta sonu, tatil, gün aşırı, 4–5 gün
  /// ara) farkı 1'i aştığında her fazla birim için ceza. Yıl içi dengenin
  /// bir hamledeki etkisinden (~2) çok büyük: önce ay içi adalet.
  static const spreadPenalty = 30.0;

  /// Nöbetler arası boşluk [ShiftGaps.maxGap]'i aştığında fazla her gün için
  /// ceza. Neredeyse kesin kural: hiçbir adalet hedefi için aşılmaz, yalnız
  /// başka türlü bir koltuk boş kalacaksa ([emptySlotPenalty]) aşılabilir.
  static const gapExcessPenalty = 150.0;

  /// 5 günlük boşluklar herkese eşit sayıda düşmezse (biri 1, diğerleri 0
  /// gibi) farkın her birimi için ceza; eşitlenemiyorsa 5 gün kimseye
  /// verilmez.
  static const unevenFivePenalty = 15.0;

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

  /// Kişinin yıl içi toplamının, çalışabildiği güne göre payından farkı
  /// (± [clamp] ile sınırlı). Pay = grubun toplamı × kişinin çalışabildiği
  /// gün / grubun çalışabildiği gün: işe sonradan başlayan ya da uzun izne
  /// çıkan kişi "eksik tutmuş" sayılmaz. Gün bilgisi yoksa grup ortalaması
  /// kullanılır. Pozitif: payından fazla tutmuş.
  static Map<String, double> relativeToShare(
    List<Person> members,
    Map<String, PersonTotals> ytd,
    int Function(PersonTotals) pick,
    double clamp,
  ) {
    if (members.isEmpty) return const {};
    final totals = {
      for (final p in members) p.id: ytd[p.id] ?? const PersonTotals(),
    };
    final sum = totals.values.fold(0, (a, t) => a + pick(t));
    final days = totals.values.fold(0, (a, t) => a + t.availableDays);
    final mean = sum / members.length;
    return {
      for (final e in totals.entries)
        e.key:
            (pick(e.value) -
                    (days > 0 ? sum * e.value.availableDays / days : mean))
                .clamp(-clamp, clamp)
                .toDouble(),
    };
  }

  /// Ayın tam gün tatilleri (arifeler hariç). [religious] verilirse yalnız
  /// dini bayramlar (true) ya da yalnız resmi tatiller (false). Resmi tatil
  /// ve dini bayram nöbetleri hafta sonundan ve birbirinden ayrı dengelenir.
  static Set<int> holidayDays(
    int year,
    int month,
    Iterable<Holiday> holidays, {
    bool? religious,
  }) => {
    for (final h in holidays)
      if (!h.isHalfDay &&
          h.date.year == year &&
          h.date.month == month &&
          (religious == null || h.isReligious == religious))
        h.date.day,
  };

  /// Gün aşırı çift sayısı: kişinin hem d hem d+2 günü nöbetçi olduğu d'ler.
  static int everyOtherDayPairs(Set<int> days) =>
      days.where((d) => days.contains(d + 2)).length;

  RosterResult generate() {
    final rng = Random(seed);
    final weekend = weekendDays(year, month, holidays, settings);
    final national = holidayDays(year, month, holidays, religious: false);
    final religious = holidayDays(year, month, holidays, religious: true);

    // Sorumlu hemşire yalnızca seçtiği günlerde nöbete yazılabilir.
    Map<String, Set<int>> availableOf(List<Person> members) => {
      for (final p in members)
        p.id: {
          for (var d = 1; d <= daysInMonth; d++)
            if (!(unavailableDays[p.id] ?? const []).contains(d) &&
                (!p.isChargeNurse ||
                    (requestedShifts[p.id]?.contains(d) ?? false)))
              d,
        },
    };

    final nurseMembers = people.where((p) => p.role == Role.nurse).toList();
    final nurses = _RoleSolver(
      role: Role.nurse,
      members: nurseMembers,
      perDay: settings.nursesPerDay,
      days: daysInMonth,
      available: availableOf(nurseMembers),
      weekend: weekend,
      national: national,
      religious: religious,
      tail: _tailFor(nurseMembers),
      absent: _absentFor(nurseMembers),
      yearToDate: yearToDate,
      allowance: _allowanceFor(nurseMembers),
      reserve: {
        for (final p in nurseMembers)
          if (p.isChargeNurse) p.id,
      },
      fixed: _fixedFor(nurseMembers),
      settings: settings,
    )._run(rng, attempts, existing, (a) => a.nurseIds);

    final techMembers = people
        .where((p) => p.role == Role.radiologyTech)
        .toList();
    final techAvailable = availableOf(techMembers);
    final techTail = _tailFor(techMembers);

    final assignments = <int, DayAssignment>{};
    final issues = <RosterIssue>[];
    double techScore;

    if (settings.techsPerDay == 2) {
      // Günde 2 tekniker: biri 24, biri 16B.
      final tech = _TechSolver(
        members: techMembers,
        days: daysInMonth,
        available: techAvailable,
        weekend: weekend,
        national: national,
        religious: religious,
        tail: techTail,
        absent: _absentFor(techMembers),
        yearToDate: yearToDate,
        allowance: _allowanceFor(techMembers),
        fixed: _fixedFor(techMembers),
        settings: settings,
      )._run(rng, attempts, existing);
      techScore = tech.score;
      for (var d = 1; d <= daysInMonth; d++) {
        assignments[d] = DayAssignment(
          day: d,
          nurseIds: [...nurses.slots[d]],
          techId: tech.slot24[d],
          tech16bId: tech.slot16[d],
        );
      }
      issues.addAll(tech.issues(month));
    } else {
      final techs = _RoleSolver(
        role: Role.radiologyTech,
        members: techMembers,
        perDay: settings.techsPerDay,
        days: daysInMonth,
        available: techAvailable,
        weekend: weekend,
        national: national,
        religious: religious,
        tail: techTail,
        absent: _absentFor(techMembers),
        yearToDate: yearToDate,
        allowance: _allowanceFor(techMembers),
        fixed: _fixedFor(techMembers),
        settings: settings,
      )._run(rng, attempts, existing, (a) => [?a.techId]);
      techScore = techs.score;
      for (var d = 1; d <= daysInMonth; d++) {
        assignments[d] = DayAssignment(
          day: d,
          nurseIds: [...nurses.slots[d]],
          techId: techs.slots[d].firstOrNull,
        );
      }
      issues.addAll(techs.issues(month));
    }

    issues
      ..addAll(nurses.issues(month))
      ..sort((a, b) => a.day.compareTo(b.day));

    return RosterResult(
      assignments: assignments,
      score: nurses.score + techScore,
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
    this.national = const {},
    this.religious = const {},
    required this.tail,
    this.absent = const {},
    required Map<String, PersonTotals> yearToDate,
    this.allowance = const {},
    this.reserve = const {},
    this.fixed = const {},
    required RosterSettings settings,
  }) : ytdShifts = _relative(
         _fair(members, reserve),
         yearToDate,
         (t) => t.shifts,
       ),
       ytdWeekend = _relative(
         _fair(members, reserve),
         yearToDate,
         (t) => t.weekendShifts,
       ),
       ytdPairs = _relative(
         _fair(members, reserve),
         yearToDate,
         (t) => t.everyOtherDayPairs,
       ),
       ytdNational = _relative(
         _fair(members, reserve),
         yearToDate,
         (t) => t.nationalHolidayShifts,
       ),
       ytdReligious = _relative(
         _fair(members, reserve),
         yearToDate,
         (t) => t.religiousHolidayShifts,
       ),
       forbidConsecutive = settings.forbidConsecutiveDays,
       maxChain = max(1, settings.maxEveryOtherDayChain),
       ids = [for (final p in members) p.id],
       fairIds = [
         for (final p in members)
           if (!reserve.contains(p.id)) p.id,
       ],
       cap =
           settings.maxExtraOverAverage == null ||
               _fair(members, reserve).isEmpty
           ? null
           : (days * perDay / _fair(members, reserve).length).ceil() +
                 settings.maxExtraOverAverage!;

  static List<Person> _fair(List<Person> members, Set<String> reserve) => [
    for (final p in members)
      if (!reserve.contains(p.id)) p,
  ];

  final Role role;
  final List<Person> members;
  final List<String> ids;

  /// Dengeye giren kişiler ([reserve] dışındakiler).
  final List<String> fairIds;

  /// Yedek kişiler (sorumlu hemşire): nöbet dengesine girmez, yalnızca
  /// başka uygun kişi yoksa nöbete yazılır.
  final Set<String> reserve;

  /// Kişi → sabit nöbet günleri: her denemede önce yazılır, yerel
  /// iyileştirmede yerinden oynatılmaz.
  final Map<String, Set<int>> fixed;

  bool _isFixed(String id, int d) => fixed[id]?.contains(d) ?? false;

  void _prefill() {
    for (final MapEntry(key: id, value: days) in fixed.entries) {
      if (!_worked.containsKey(id)) continue;
      for (final d in days) {
        if (_slots[d].length < perDay && !_worked[id]!.contains(d)) {
          _add(id, d);
        }
      }
    }
  }

  /// Yedek kişinin her nöbetinin cezası: boş koltuktan ucuz, dengeyi
  /// bozan her hamleden pahalı.
  static const _reservePenalty = 200.0;

  final int perDay;
  final int days;
  final Map<String, Set<int>> available;
  final Set<int> weekend;

  /// Tam gün resmi (ulusal) tatiller; nöbetleri ayrıca dengelenir.
  final Set<int> national;

  /// Tam gün dini bayramlar; nöbetleri resmi tatillerden ayrı dengelenir.
  final Set<int> religious;
  final Map<String, Set<int>> tail;

  /// Kişi → izinli / pasif günler (boşluk hesabında aralığı keser).
  final Map<String, Set<int>> absent;

  /// Boşluk taramasının başladığı gün: önceki ay kuyruğunun en eski günü.
  late final int _tailStart = tail.values.fold(
    1,
    (m, days) => days.fold(m, (a, d) => d < a ? d : a),
  );
  final bool forbidConsecutive;
  final int maxChain;
  final int? cap;

  /// Kişi → fazla mesai payı (fazla mesai isteyene > 0). Nöbet sayısı
  /// dengelenirken bu kadar fazlası hoş görülür.
  final Map<String, int> allowance;

  int _allow(String id) => allowance[id] ?? 0;

  /// Kişinin yıl içi toplamının grup ortalamasından farkı, ±[_ytdClamp]
  /// ile sınırlı. Pozitif: yıl içinde diğerlerinden fazla tutmuş.
  final Map<String, double> ytdShifts;
  final Map<String, double> ytdWeekend;
  final Map<String, double> ytdPairs;
  final Map<String, double> ytdNational;
  final Map<String, double> ytdReligious;

  /// Yıllık tatil terimlerinin ek çarpanı: dört yıllık terimin bir hamledeki
  /// toplam etkisi (4,8 + 0,8 = 5,6) ay içi dengeyi bozmanın bedelinden (6)
  /// küçük kalsın. Bir gün ya resmi tatil ya dini bayram olduğundan bir
  /// hamle bu iki terimden yalnız birini değiştirir.
  static const _ytdHolidayScale = 0.5;

  static const _ytdClamp = 2.0;

  /// Ay içi sapma karelerinin ağırlığı. Ay içi dengeyi bozan en küçük
  /// değişiklik (ör. 9-9 → 10-8) 2 × 3 = 6 puandır.
  static const _balanceWeight = 3.0;

  /// Yıllık denge teriminin ağırlığı. Öncelik ay içi adalettir: bir hamle
  /// yıllık terimlerin her birini en fazla 2 × 2 × 0,3 = 1,2, hepsini birden
  /// (tatil terimleri yarım) en fazla 4,8 puan değiştirir; ay içi dengeyi
  /// bozmanın bedeli ise en az 6 puandır (fark 1'i aşarsa ayrıca
  /// [RosterGenerator.spreadPenalty]). Böylece yıllık denge yalnızca ay içi
  /// denge eşitken ("fazla nöbet kime") seçimi belirler, ay içi farkı
  /// hiçbir zaman büyütmez.
  static const _ytdWeight = 0.3;

  /// Açgözlü adımda yıllık farkın her birimi için ceza; ay içi farkın bir
  /// birimi 10 puan olduğundan en fazla 2 × 1 = 2 puanla onun altında kalır.
  static const _ytdGreedyWeight = 1.0;

  static Map<String, double> _relative(
    List<Person> members,
    Map<String, PersonTotals> ytd,
    int Function(PersonTotals) pick,
  ) {
    return RosterGenerator.relativeToShare(members, ytd, pick, _ytdClamp);
  }

  late List<List<String>> _slots;
  late Map<String, Set<int>> _worked;

  int get _totalSlots => days * perDay;

  void _reset() {
    _slots = List.generate(days + 1, (_) => <String>[]);
    _worked = {for (final id in ids) id: <int>{}};
    _weekendN = {for (final id in ids) id: 0};
    _nationalN = {for (final id in ids) id: 0};
    _religiousN = {for (final id in ids) id: 0};
    _pairsN = {for (final id in ids) id: 0};
  }

  // Sayaçlar: puan hesabında her seferinde baştan saymamak için _add /
  // _remove ile güncellenir.
  late Map<String, int> _weekendN;
  late Map<String, int> _nationalN;
  late Map<String, int> _religiousN;
  late Map<String, int> _pairsN;

  void _count(String id, int d, int delta) {
    final w = _worked[id]!;
    if (weekend.contains(d)) _weekendN[id] = _weekendN[id]! + delta;
    if (national.contains(d)) _nationalN[id] = _nationalN[id]! + delta;
    if (religious.contains(d)) _religiousN[id] = _religiousN[id]! + delta;
    final pairs = (w.contains(d - 2) ? 1 : 0) + (w.contains(d + 2) ? 1 : 0);
    _pairsN[id] = _pairsN[id]! + delta * pairs;
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
    _count(id, d, 1);
  }

  void _remove(String id, int d) {
    _slots[d].remove(id);
    _worked[id]!.remove(d);
    _count(id, d, -1);
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
    if (cap != null &&
        !reserve.contains(id) &&
        _worked[id]!.length >= cap! + _allow(id)) {
      return _Block.cap;
    }
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

  int _weekendCount(String id) => _weekendN[id]!;

  int _nationalCount(String id) => _nationalN[id]!;

  int _religiousCount(String id) => _religiousN[id]!;

  int _pairs(String id) => _pairsN[id]!;

  /// Rol puanı: grup içi sapmaların kareleri + toplam çift cezası + boş
  /// koltuk cezası.
  double _score() {
    var reserveShifts = 0;
    for (final id in reserve) {
      reserveShifts += _worked[id]?.length ?? 0;
    }
    final reserveCost = reserveShifts * _reservePenalty;
    final ids = fairIds;
    if (ids.isEmpty) {
      return _emptySlots() * RosterGenerator.emptySlotPenalty + reserveCost;
    }
    final n = ids.length;
    // Fazla mesai isteyenin payı sayısından düşülür: böylece birkaç fazla
    // nöbet dengesizlik sayılmaz ve o kişi fazlayı üstlenir.
    final counts = [for (final id in ids) _worked[id]!.length - _allow(id)];
    final weekends = [for (final id in ids) _weekendCount(id)];
    final nationals = [for (final id in ids) _nationalCount(id)];
    final religiouses = [for (final id in ids) _religiousCount(id)];
    final pairs = [for (final id in ids) _pairs(id)];

    double sq(List<int> values) {
      final mean = values.fold(0, (a, b) => a + b) / n;
      return values.fold(0.0, (s, v) => s + (v - mean) * (v - mean));
    }

    double yearly(List<int> values, Map<String, double> ytd) {
      var sum = 0.0;
      for (var i = 0; i < n; i++) {
        sum += values[i] * ytd[ids[i]]!;
      }
      return sum * _ytdWeight;
    }

    final totalPairs = pairs.fold(0, (a, b) => a + b);
    // Nöbetler arası boşluk: 5 günü aşan her gün cezalı; 4–5 günlük
    // boşluk sayısı kişiler arasında dengelenir.
    var gapExcess = 0;
    final longGaps = <int>[];
    final fives = <int>[];
    for (final id in ids) {
      final off = absent[id];
      final (excess, long, five) = ShiftGaps.scan(
        from: _tailStart,
        to: days,
        works: (d) => _works(id, d),
        isAbsent: off == null || off.isEmpty ? null : off.contains,
        openEnd: true,
      );
      gapExcess += excess;
      longGaps.add(long);
      fives.add(five);
    }
    // Ay içi fark 1'i aşarsa güçlü ceza: ay içi adalet her zaman yıl içi
    // dengeden önce gelir.
    int over(List<int> values) {
      if (values.isEmpty) return 0;
      final spread = values.reduce(max) - values.reduce(min);
      return spread > 1 ? spread - 1 : 0;
    }

    return _balanceWeight *
            (sq(counts) +
                sq(weekends) +
                sq(nationals) +
                sq(religiouses) +
                sq(pairs) +
                sq(longGaps)) +
        RosterGenerator.spreadPenalty *
            (over(counts) +
                over(weekends) +
                over(nationals) +
                over(religiouses) +
                over(pairs) +
                over(longGaps)) +
        RosterGenerator.gapExcessPenalty * gapExcess +
        RosterGenerator.unevenFivePenalty * ShiftGaps.unevenMaxGaps(fives) +
        yearly(counts, ytdShifts) +
        yearly(weekends, ytdWeekend) +
        yearly(nationals, ytdNational) * _ytdHolidayScale +
        yearly(religiouses, ytdReligious) * _ytdHolidayScale +
        yearly(pairs, ytdPairs) +
        0.75 * totalPairs +
        _emptySlots() * RosterGenerator.emptySlotPenalty +
        RosterGenerator.changePenalty * _changes() +
        reserveCost;
  }

  int _emptySlots() {
    var empty = 0;
    for (var d = 1; d <= days; d++) {
      empty += perDay - _slots[d].length;
    }
    return empty;
  }

  /// Sıfırdan çözüm ya da ([existing] verilirse) mevcut listeyi düzeltme.
  _RoleSolution _run(
    Random rng,
    int attempts,
    Map<int, DayAssignment>? existing,
    List<String> Function(DayAssignment) seats,
  ) => existing == null
      ? solve(rng, attempts, RosterGenerator._polishCount)
      : solveFrom(rng, [
          const <String>[],
          for (var d = 1; d <= days; d++)
            if (existing[d] case final a?) seats(a) else const <String>[],
        ]);

  /// Düzeltme modunda başlangıç listesi; puana değişiklik cezası eklenir.
  List<Set<String>>? _original;

  int _changes() {
    final original = _original;
    if (original == null) return 0;
    var n = 0;
    for (var d = 1; d <= days; d++) {
      for (final id in _slots[d]) {
        if (!original[d].contains(id)) n++;
      }
    }
    return n;
  }

  /// Mevcut listeden başlayıp düzeltir: kural bozan atamalar alınmaz,
  /// sonra yerel iyileştirme boşlukları doldurur ve kuralları düzeltir.
  _RoleSolution solveFrom(Random rng, List<List<String>> slots) {
    _reset();
    _original = [for (final s in slots) s.toSet()];
    if (perDay <= 0) return _RoleSolution(this, _snapshot(), 0);
    _prefill();
    for (var d = 1; d <= days; d++) {
      for (final id in slots[d]) {
        if (_slots[d].length >= perDay) break;
        if (!ids.contains(id) || _block(id, d) != null) continue;
        _add(id, d);
      }
    }
    _improve(rng);
    return _RoleSolution(this, _snapshot(), _score());
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
      _improve(rng, chain: false);
      final score = _score();
      if (score < best.$1) best = (score, _snapshot());
    }
    // Pahalı zincirli değiştirme yalnız en iyi sonuca uygulanır.
    _load(best.$2);
    _improve(rng);
    final score = _score();
    if (score < best.$1) best = (score, _snapshot());
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

    _prefill();
    for (final d in order) {
      while (_slots[d].length < perDay) {
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
    // Yedek kişi yalnızca başka aday kalmazsa seçilsin.
    if (reserve.contains(id)) return 1e6 + _worked[id]!.length;
    final n = fairIds.length;
    // Fazla mesai payı sayıdan düşülünce o kişi fazla nöbet için öne geçer.
    var cost = (_worked[id]!.length - _allow(id) + 1 - _totalSlots / n) * 10;
    cost += ytdShifts[id]! * _ytdGreedyWeight;
    if (weekend.contains(d)) {
      cost += (_weekendCount(id) + 1 - weekend.length * perDay / n) * 10;
      cost += ytdWeekend[id]! * _ytdGreedyWeight;
    }
    if (national.contains(d)) {
      cost += (_nationalCount(id) + 1 - national.length * perDay / n) * 10;
      cost += ytdNational[id]! * _ytdGreedyWeight;
    }
    if (religious.contains(d)) {
      cost += (_religiousCount(id) + 1 - religious.length * perDay / n) * 10;
      cost += ytdReligious[id]! * _ytdGreedyWeight;
    }
    final newPairs =
        (d - 2 >= 1 && _works(id, d - 2) ? 1 : 0) + (_works(id, d + 2) ? 1 : 0);
    if (newPairs > 0) {
      final meanPairs = fairIds.map(_pairs).fold(0, (a, b) => a + b) / n;
      cost += newPairs * ((_pairs(id) + 1 - meanPairs) * 10 + 3);
      cost += newPairs * ytdPairs[id]! * _ytdGreedyWeight;
    }
    // Nöbetler aralıklı dağılsın: 3 gün arayla nöbete küçük ceza.
    if (_works(id, d - 3) || _works(id, d + 3)) cost += 1;
    return cost;
  }

  /// Yerel iyileştirme: puanı düşüren hamle kalmayana kadar.
  void _improve(Random rng, {bool chain = true}) {
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
      // Kaydırma: boş koltuğa doğrudan kimse yazılamıyorsa, başka bir
      // nöbetini bırakınca yazılabilen biri kaydırılır; bıraktığı koltuğa
      // o gün boşta olan biri geçer (düzeltme modunda önemli).
      for (var d = 1; d <= days; d++) {
        while (_slots[d].length < perDay && _shiftInto(d)) {
          improved = true;
        }
      }
      if (improved) current = _score();

      // Değiştirme: d günündeki a yerine b.
      for (var d = 1; d <= days; d++) {
        for (final a in [..._slots[d]]) {
          if (_isFixed(a, d)) continue;
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
          if (_isFixed(a, d1) || _isFixed(b, d2)) continue;
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

      // Basit hamleler tükenince zincirli değiştirme dene.
      if (chain && !improved && _tryChain(current)) {
        current = _score();
        improved = true;
      }

      // Sonra iki kişinin bir dilimdeki nöbetlerini takas et: tek
      // nöbetlik hamlelerin bozmadan yapamadığı "fazla nöbet kime" seçimini
      // (yıl içi denge) düzeltir. Pahalı olduğundan yalnız en iyi sonuca ve
      // nöbet sayısı farklı (fazla nöbetin el değiştirebileceği) çiftlere
      // uygulanır; diğer çiftlerde yalnız ay sonuna kadar takas denenir.
      if (chain && !improved) {
        for (var i = 0; i < fairIds.length; i++) {
          for (var j = i + 1; j < fairIds.length; j++) {
            final a = fairIds[i];
            final b = fairIds[j];
            final all = _worked[a]!.length != _worked[b]!.length;
            for (var from = 1; from <= days; from++) {
              for (var to = all ? from : days; to <= days; to++) {
                final countsOnly = to < days;
                if (_tryRangeSwap(
                  a,
                  b,
                  from,
                  to,
                  current,
                  countsOnly: countsOnly,
                )) {
                  current = _score();
                  improved = true;
                }
              }
            }
          }
        }
      }

      if (!improved) break;
    }
  }

  /// Boş [d] koltuğunu kaydırmayla doldurur: x kişisi e günündeki nöbetini
  /// bırakıp d'ye geçer, e'ye o gün yazılabilen y gelir. Boş koltuk sayısı
  /// bir azalırsa true; olmazsa her şey eski hâline döner.
  bool _shiftInto(int d) {
    for (final x in ids) {
      if (_slots[d].contains(x) || !available[x]!.contains(d)) continue;
      for (final e in [..._worked[x]!]..sort()) {
        if (_isFixed(x, e)) continue;
        _remove(x, e);
        if (_block(x, d) == null) {
          _add(x, d);
          String? best;
          for (final y in ids) {
            if (y == x || _block(y, e) != null) continue;
            // Yedek kişi (sorumlu hemşire) en son; sonra en az nöbetli.
            if (best == null ||
                (reserve.contains(best) && !reserve.contains(y)) ||
                (reserve.contains(best) == reserve.contains(y) &&
                    _worked[y]!.length < _worked[best]!.length)) {
              best = y;
            }
          }
          if (best != null) {
            _add(best, e);
            return true;
          }
          _remove(x, d);
        }
        _add(x, e);
      }
    }
    return false;
  }

  /// Zincirli değiştirme: d1 günündeki a yerine b yazılır, b'nin d2 günündeki
  /// nöbeti c'ye geçer (c = a ise takas). Tek takasın kurallara takıldığı
  /// durumlarda (ör. hafta sonlarının çoğunu istemeyen kişiye kalan hafta
  /// sonunu vermek) dengeyi düzeltir. İlk iyileştirmede kalıcı yapar.
  bool _tryChain(double current) {
    for (var d1 = 1; d1 <= days; d1++) {
      for (final a in [..._slots[d1]]) {
        if (_isFixed(a, d1)) continue;
        for (final b in ids) {
          if (_slots[d1].contains(b) || !available[b]!.contains(d1)) continue;
          for (final d2 in [..._worked[b]!]) {
            if (d2 == d1 || _isFixed(b, d2)) continue;
            _remove(a, d1);
            _remove(b, d2);
            if (_block(b, d1) == null) {
              _add(b, d1);
              for (final c in ids) {
                if (c == b || _block(c, d2) != null) continue;
                _add(c, d2);
                if (_score() < current - 1e-9) return true;
                _remove(c, d2);
              }
              _remove(b, d1);
            }
            _add(b, d2);
            _add(a, d1);
          }
        }
      }
    }
    return false;
  }

  /// [a] ile [b]'nin [from]–[to] günleri arasındaki tüm nöbetlerini takas
  /// eder; kurallar bozulmuyor ve puan düşüyorsa bırakır.
  /// [countsOnly]: nöbet sayılarını değiştirmeyen takas denenmez.
  bool _tryRangeSwap(
    String a,
    String b,
    int from,
    int to,
    double current, {
    bool countsOnly = false,
  }) {
    final moves = <int>[
      for (var d = from; d <= to; d++)
        if (_worked[a]!.contains(d) != _worked[b]!.contains(d)) d,
    ];
    if (moves.isEmpty) return false;
    if (countsOnly &&
        moves.where(_worked[a]!.contains).length * 2 == moves.length) {
      return false;
    }
    for (final d in moves) {
      if (_isFixed(a, d) || _isFixed(b, d)) return false;
    }
    void swap() {
      for (final d in moves) {
        final (x, y) = _worked[a]!.contains(d) ? (a, b) : (b, a);
        _remove(x, d);
        _add(y, d);
      }
    }

    swap();
    if (_valid(a) && _valid(b) && _score() < current - 1e-9) return true;
    swap();
    return false;
  }

  /// Kişinin tüm nöbetleri kurallara uyuyor mu?
  bool _valid(String id) {
    final worked = _worked[id]!;
    if (cap != null &&
        !reserve.contains(id) &&
        worked.length > cap! + _allow(id)) {
      return false;
    }
    for (final d in worked) {
      if (!available[id]!.contains(d)) return false;
      if (forbidConsecutive && (_works(id, d - 1) || _works(id, d + 1))) {
        return false;
      }
      if (_breaksChain(id, d)) return false;
    }
    return true;
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
        _Block.unavailable =>
          reserve.contains(p.id)
              ? 'sorumlu hemşire, bu günü seçmedi'
              : 'istemiyor ya da izinli',
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

/// Günde 2 tekniker çözümü: her gün bir 24 (ağır, ertesi gün çalışılamaz) ve
/// bir 16B (hafif, ertesi gün çalışılabilir) teknikeri.
class _TechSolution {
  _TechSolution(this.solver, this.slot24, this.slot16, this.score);

  final _TechSolver solver;

  /// Gün → 24 teknikeri (boşsa null). İndeks 0 kullanılmaz.
  final List<String?> slot24;

  /// Gün → 16B teknikeri (boşsa null).
  final List<String?> slot16;
  final double score;

  Iterable<RosterIssue> issues(int month) sync* {
    for (var d = 1; d < slot24.length; d++) {
      if (slot24[d] == null) {
        yield solver.describeGap(d, is16b: false, month: month);
      }
      if (slot16[d] == null) {
        yield solver.describeGap(d, is16b: true, month: month);
      }
    }
  }
}

/// Teknikerleri 24 + 16B olarak dağıtır (saf Dart).
///
/// Kurallar: 24 çalışan ertesi gün hiç çalışamaz; 16B çalışan ertesi gün
/// çalışabilir; gün aşırı zincir sınırı yalnız 24'lere uygulanır. Adalet:
/// 24 sayıları, 16B sayıları ve hafta sonu sayıları grup içinde eşitlenir.
class _TechSolver {
  _TechSolver({
    required this.members,
    required this.days,
    required this.available,
    required this.weekend,
    this.national = const {},
    this.religious = const {},
    required this.tail,
    this.absent = const {},
    required Map<String, PersonTotals> yearToDate,
    this.allowance = const {},
    this.fixed = const {},
    required RosterSettings settings,
  }) : ids = [for (final p in members) p.id],
       maxChain = max(1, settings.maxEveryOtherDayChain),
       cap = settings.maxExtraOverAverage == null || members.isEmpty
           ? null
           : (2 * days / members.length).ceil() +
                 2 * settings.maxExtraOverAverage!,
       ytd = _TechSolver._relative(members, yearToDate, (t) => t.shifts),
       ytdNational = _TechSolver._relative(
         members,
         yearToDate,
         (t) => t.nationalHolidayShifts,
       ),
       ytdReligious = _TechSolver._relative(
         members,
         yearToDate,
         (t) => t.religiousHolidayShifts,
       );

  final List<Person> members;
  final List<String> ids;
  final int days;
  final Map<String, Set<int>> available;
  final Set<int> weekend;

  /// Tam gün resmi (ulusal) tatiller; nöbetleri ayrıca dengelenir.
  final Set<int> national;

  /// Tam gün dini bayramlar; nöbetleri resmi tatillerden ayrı dengelenir.
  final Set<int> religious;

  /// Kişi → fazla mesai payı; 24 sayısı dengesinde bu kadarı hoş görülür.
  final Map<String, int> allowance;

  /// Kişi → mutlaka nöbet tutacağı günler (ör. şua dönüşü): her denemede
  /// önce yazılır (24, olmazsa 16B), yerel iyileştirmede oynatılmaz.
  final Map<String, Set<int>> fixed;

  bool _isFixed(String id, int d) => fixed[id]?.contains(d) ?? false;

  void _prefill() {
    for (final MapEntry(key: id, value: days) in fixed.entries) {
      if (!_w24.containsKey(id)) continue;
      for (final d in days.toList()..sort()) {
        if (_slot24[d] == id || _slot16[d] == id) continue;
        if (_canPlace24(id, d)) {
          _place24(id, d);
        } else if (_canPlace16(id, d)) {
          _place16(id, d);
        }
      }
    }
  }

  int _allow(String id) => allowance[id] ?? 0;

  /// Kişi → önceki aya ait çalıştığı günler (offset ≤ 0). Hepsi 24 (bloklayan)
  /// kabul edilir.
  final Map<String, Set<int>> tail;

  /// Kişi → izinli / pasif günler (boşluk hesabında aralığı keser).
  final Map<String, Set<int>> absent;

  /// Boşluk taramasının başladığı gün: önceki ay kuyruğunun en eski günü.
  late final int _tailStart = tail.values.fold(
    1,
    (m, days) => days.fold(m, (a, d) => d < a ? d : a),
  );
  final int maxChain;
  final int? cap;
  final Map<String, double> ytd;
  final Map<String, double> ytdNational;
  final Map<String, double> ytdReligious;

  late List<String?> _slot24;
  late List<String?> _slot16;
  late Map<String, Set<int>> _w24;
  late Map<String, Set<int>> _w16;

  static const _ytdClamp = 2.0;

  static Map<String, double> _relative(
    List<Person> members,
    Map<String, PersonTotals> ytd,
    int Function(PersonTotals) pick,
  ) {
    return RosterGenerator.relativeToShare(members, ytd, pick, _ytdClamp);
  }

  void _reset() {
    _slot24 = List.filled(days + 1, null);
    _slot16 = List.filled(days + 1, null);
    _w24 = {for (final id in ids) id: <int>{}};
    _w16 = {for (final id in ids) id: <int>{}};
  }

  void _load(List<String?> s24, List<String?> s16) {
    _reset();
    for (var d = 1; d <= days; d++) {
      if (s24[d] case final id?) _place24(id, d);
      if (s16[d] case final id?) _place16(id, d);
    }
  }

  void _place24(String id, int d) {
    _slot24[d] = id;
    _w24[id]!.add(d);
  }

  void _place16(String id, int d) {
    _slot16[d] = id;
    _w16[id]!.add(d);
  }

  void _remove24(int d) {
    final id = _slot24[d];
    if (id != null) _w24[id]!.remove(d);
    _slot24[d] = null;
  }

  void _remove16(int d) {
    final id = _slot16[d];
    if (id != null) _w16[id]!.remove(d);
    _slot16[d] = null;
  }

  bool _has24(String id, int d) =>
      d <= 0 ? (tail[id]?.contains(d) ?? false) : _w24[id]!.contains(d);

  bool _worksAny(String id, int d) {
    if (d <= 0) return tail[id]?.contains(d) ?? false;
    if (d > days) return false;
    return _slot24[d] == id || _slot16[d] == id;
  }

  bool _breaks24Chain(String id, int d) {
    for (var j = 0; j <= maxChain; j++) {
      final start = d - 2 * j;
      var full = true;
      for (var k = 0; k <= maxChain && full; k++) {
        final day = start + 2 * k;
        if (day != d && !_has24(id, day)) full = false;
      }
      if (full) return true;
    }
    return false;
  }

  bool _overCap(String id) =>
      cap != null && _w24[id]!.length + _w16[id]!.length >= cap! + _allow(id);

  bool _canPlace24(String id, int d) =>
      available[id]!.contains(d) &&
      _slot24[d] == null &&
      _slot16[d] != id &&
      !_worksAny(id, d) &&
      !_has24(id, d - 1) &&
      !_worksAny(id, d + 1) &&
      !_breaks24Chain(id, d) &&
      !_overCap(id);

  bool _canPlace16(String id, int d) =>
      available[id]!.contains(d) &&
      _slot16[d] == null &&
      _slot24[d] != id &&
      !_worksAny(id, d) &&
      !_has24(id, d - 1) &&
      !_overCap(id);

  int _weekendCount(String id) =>
      _w24[id]!.where(weekend.contains).length +
      _w16[id]!.where(weekend.contains).length;

  int _nationalCount(String id) =>
      _w24[id]!.where(national.contains).length +
      _w16[id]!.where(national.contains).length;

  int _religiousCount(String id) =>
      _w24[id]!.where(religious.contains).length +
      _w16[id]!.where(religious.contains).length;

  int _pairs24(String id) => RosterGenerator.everyOtherDayPairs(_w24[id]!);

  int _emptySlots() {
    var empty = 0;
    for (var d = 1; d <= days; d++) {
      if (_slot24[d] == null) empty++;
      if (_slot16[d] == null) empty++;
    }
    return empty;
  }

  double _score() {
    final empty = _emptySlots() * RosterGenerator.emptySlotPenalty;
    if (ids.isEmpty) return empty;
    final n = ids.length;
    double sq(int Function(String) pick) {
      final values = [for (final id in ids) pick(id)];
      final mean = values.fold(0, (a, b) => a + b) / n;
      return values.fold(0.0, (s, v) => s + (v - mean) * (v - mean));
    }

    // Ay içi fark 1'i aşarsa güçlü ceza (hemşirelerdeki gibi).
    int over(int Function(String) pick) {
      var lo = 1 << 30, hi = -1;
      for (final id in ids) {
        final v = pick(id);
        if (v < lo) lo = v;
        if (v > hi) hi = v;
      }
      return hi - lo > 1 ? hi - lo - 1 : 0;
    }

    final totalPairs = ids.fold(0, (a, id) => a + _pairs24(id));
    var gapExcess = 0;
    final longById = <String, int>{};
    final fives = <int>[];
    for (final id in ids) {
      final off = absent[id];
      final t = tail[id];
      final (excess, long, five) = ShiftGaps.scan(
        from: _tailStart,
        to: days,
        works: (d) => d <= 0
            ? (t?.contains(d) ?? false)
            : _w24[id]!.contains(d) || _w16[id]!.contains(d),
        isAbsent: off == null || off.isEmpty ? null : off.contains,
        openEnd: true,
      );
      gapExcess += excess;
      longById[id] = long;
      fives.add(five);
    }
    int longGaps(String id) => longById[id]!;
    const balance = 3.0;
    return RosterGenerator.gapExcessPenalty * gapExcess +
        RosterGenerator.unevenFivePenalty * ShiftGaps.unevenMaxGaps(fives) +
        balance * sq(longGaps) +
        balance *
            (sq((id) => _w24[id]!.length - _allow(id)) +
                sq((id) => _w16[id]!.length) +
                sq(_weekendCount) +
                sq(_nationalCount) +
                sq(_religiousCount) +
                sq(_pairs24)) +
        RosterGenerator.spreadPenalty *
            (over(longGaps) +
                over((id) => _w24[id]!.length - _allow(id)) +
                over((id) => _w16[id]!.length) +
                over(_weekendCount) +
                over(_nationalCount) +
                over(_religiousCount) +
                over(_pairs24)) +
        0.75 * totalPairs +
        RosterGenerator.changePenalty * _changes() +
        empty;
  }

  _TechSolution _run(
    Random rng,
    int attempts,
    Map<int, DayAssignment>? existing,
  ) {
    if (existing == null) {
      return solve(rng, attempts, RosterGenerator._polishCount);
    }
    _reset();
    _original24 = [null, for (var d = 1; d <= days; d++) existing[d]?.techId];
    _original16 = [
      null,
      for (var d = 1; d <= days; d++) existing[d]?.tech16bId,
    ];
    if (ids.isEmpty) return _TechSolution(this, [..._slot24], [..._slot16], 0);
    _prefill();
    for (var d = 1; d <= days; d++) {
      final a = _original24![d];
      if (a != null && ids.contains(a) && _canPlace24(a, d)) _place24(a, d);
      final b = _original16![d];
      if (b != null && ids.contains(b) && _canPlace16(b, d)) _place16(b, d);
    }
    _improve(rng);
    return _TechSolution(this, [..._slot24], [..._slot16], _score());
  }

  /// Düzeltme modunda başlangıç listesi.
  List<String?>? _original24;
  List<String?>? _original16;

  int _changes() {
    final o24 = _original24;
    final o16 = _original16;
    if (o24 == null || o16 == null) return 0;
    var n = 0;
    for (var d = 1; d <= days; d++) {
      if (_slot24[d] != null && _slot24[d] != o24[d]) n++;
      if (_slot16[d] != null && _slot16[d] != o16[d]) n++;
    }
    return n;
  }

  _TechSolution solve(Random rng, int attempts, int polishCount) {
    _reset();
    if (ids.isEmpty) return _TechSolution(this, [..._slot24], [..._slot16], 0);

    final candidates = <(double, List<String?>, List<String?>)>[];
    for (var i = 0; i < max(1, attempts); i++) {
      _greedy(rng, chronological: i.isEven);
      candidates.add((_score(), [..._slot24], [..._slot16]));
    }
    candidates.sort((a, b) => a.$1.compareTo(b.$1));

    var best = candidates.first;
    for (final c in candidates.take(polishCount)) {
      _load(c.$2, c.$3);
      _improve(rng, deep: false);
      final score = _score();
      if (score < best.$1) best = (score, [..._slot24], [..._slot16]);
    }
    // Pahalı takas yalnız en iyi sonuca uygulanır.
    _load(best.$2, best.$3);
    _improve(rng);
    final score = _score();
    if (score < best.$1) best = (score, [..._slot24], [..._slot16]);
    _load(best.$2, best.$3);
    return _TechSolution(this, best.$2, best.$3, best.$1);
  }

  void _greedy(Random rng, {required bool chronological}) {
    _reset();
    final order = [for (var d = 1; d <= days; d++) d];
    if (!chronological) {
      final availableCount = {
        for (final d in order)
          d: ids.where((id) => available[id]!.contains(d)).length,
      };
      final tie = {for (final d in order) d: rng.nextDouble()};
      order.sort((a, b) {
        final c = availableCount[a]!.compareTo(availableCount[b]!);
        return c != 0 ? c : tie[a]!.compareTo(tie[b]!);
      });
    }
    _prefill();
    for (final d in order) {
      _fillDay(d, rng);
    }
  }

  void _fillDay(int d, Random rng) {
    // Önce 24 (daha kısıtlı), sonra 16B.
    final id24 = _pick(d, rng, is16b: false);
    if (id24 != null) _place24(id24, d);
    final id16 = _pick(d, rng, is16b: true);
    if (id16 != null) _place16(id16, d);
  }

  String? _pick(int d, Random rng, {required bool is16b}) {
    String? best;
    var bestCost = double.infinity;
    for (final id in ids) {
      if (is16b ? !_canPlace16(id, d) : !_canPlace24(id, d)) continue;
      final cost = _cost(id, d, is16b: is16b) + rng.nextDouble() * 2;
      if (cost < bestCost) {
        bestCost = cost;
        best = id;
      }
    }
    return best;
  }

  double _cost(String id, int d, {required bool is16b}) {
    final n = ids.length;
    final mean = days / n; // her gün 1 adet 24 ve 1 adet 16B
    // Fazla mesai payı yalnız 24 (ağır) vardiyaya uygulanır.
    final own = is16b ? _w16[id]!.length : _w24[id]!.length - _allow(id);
    var cost = (own + 1 - mean) * 10 + ytd[id]! * 1.0;
    if (weekend.contains(d)) {
      cost += (_weekendCount(id) + 1 - weekend.length * 2 / n) * 10;
    }
    if (national.contains(d)) {
      cost += (_nationalCount(id) + 1 - national.length * 2 / n) * 10;
      cost += ytdNational[id]! * 1.0;
    }
    if (religious.contains(d)) {
      cost += (_religiousCount(id) + 1 - religious.length * 2 / n) * 10;
      cost += ytdReligious[id]! * 1.0;
    }
    if (!is16b) {
      final newPairs =
          (d - 2 >= 1 && _has24(id, d - 2) ? 1 : 0) +
          (_has24(id, d + 2) ? 1 : 0);
      if (newPairs > 0) {
        final meanPairs = ids.map(_pairs24).fold(0, (a, b) => a + b) / n;
        cost += newPairs * ((_pairs24(id) + 1 - meanPairs) * 10 + 3);
      }
    }
    return cost;
  }

  void _improve(Random rng, {bool deep = true}) {
    var current = _score();
    for (var pass = 0; pass < 30; pass++) {
      var improved = false;

      // Boş koltukları doldur.
      for (var d = 1; d <= days; d++) {
        if (_slot24[d] == null) {
          final id = _pick(d, rng, is16b: false);
          if (id != null) {
            _place24(id, d);
            improved = true;
          }
        }
        if (_slot16[d] == null) {
          final id = _pick(d, rng, is16b: true);
          if (id != null) {
            _place16(id, d);
            improved = true;
          }
        }
      }
      if (improved) current = _score();

      // Her koltukta kişiyi başkasıyla değiştir.
      for (var d = 1; d <= days; d++) {
        for (final is16b in const [false, true]) {
          final a = is16b ? _slot16[d] : _slot24[d];
          if (a == null || _isFixed(a, d)) continue;
          for (final b in ids) {
            if (b == a) continue;
            if (is16b) {
              _remove16(d);
              if (_canPlace16(b, d)) {
                _place16(b, d);
                if (_score() < current - 1e-9) {
                  current = _score();
                  improved = true;
                  break;
                }
                _remove16(d);
              }
              _place16(a, d);
            } else {
              _remove24(d);
              if (_canPlace24(b, d)) {
                _place24(b, d);
                if (_score() < current - 1e-9) {
                  current = _score();
                  improved = true;
                  break;
                }
                _remove24(d);
              }
              _place24(a, d);
            }
          }
        }
      }

      // Aynı tür iki koltuğu takas et.
      for (final is16b in const [false, true]) {
        final slot = is16b ? _slot16 : _slot24;
        final filled = [
          for (var d = 1; d <= days; d++)
            if (slot[d] != null) d,
        ];
        for (var i = 0; i < filled.length; i++) {
          for (var j = i + 1; j < filled.length; j++) {
            final d1 = filled[i];
            final d2 = filled[j];
            final a = slot[d1];
            final b = slot[d2];
            if (a == null || b == null || a == b) continue;
            if (_isFixed(a, d1) || _isFixed(b, d2)) continue;
            if (_trySwap(a, d1, b, d2, is16b: is16b, current: current)) {
              current = _score();
              improved = true;
            }
          }
        }
      }

      // Basit hamleler tükenince iki kişinin bir günden ay sonuna kadarki
      // vardiyalarını takas et. Küçük ekipte (ör. 3 tekniker) her gün bir
      // önceki güne bağlı olduğundan tek koltuk hamleleri takılır; bu hamle
      // zinciri bütün olarak kaydırır.
      for (var i = 0; deep && i < ids.length && !improved; i++) {
        for (var j = i + 1; j < ids.length; j++) {
          for (var from = 2; from <= days; from++) {
            if (_trySuffixSwap(ids[i], ids[j], from, current: current)) {
              current = _score();
              improved = true;
            }
          }
        }
      }

      if (!improved) break;
    }
  }

  /// [a] ile [b]'nin [from] gününden itibaren tüm 24 ve 16B koltuklarını
  /// takas eder; kurallar bozulmuyor ve puan düşüyorsa bırakır.
  bool _trySuffixSwap(String a, String b, int from, {required double current}) {
    void swap() {
      for (var d = from; d <= days; d++) {
        final s24 = _slot24[d];
        final s16 = _slot16[d];
        final n24 = s24 == a ? b : (s24 == b ? a : s24);
        final n16 = s16 == a ? b : (s16 == b ? a : s16);
        if (n24 != s24) {
          _remove24(d);
          if (n24 != null) _place24(n24, d);
        }
        if (n16 != s16) {
          _remove16(d);
          if (n16 != null) _place16(n16, d);
        }
      }
    }

    var touches = false;
    for (var d = from; d <= days; d++) {
      if (_isFixed(a, d) || _isFixed(b, d)) return false;
      touches =
          touches || [_slot24[d], _slot16[d]].any((x) => x == a || x == b);
    }
    if (!touches) return false;
    swap();
    if (_valid(a) && _valid(b) && _score() < current - 1e-9) return true;
    swap();
    return false;
  }

  /// Kişinin tüm vardiyaları kurallara uyuyor mu?
  bool _valid(String id) {
    if (cap != null &&
        _w24[id]!.length + _w16[id]!.length > cap! + _allow(id)) {
      return false;
    }
    for (final d in _w24[id]!) {
      if (!available[id]!.contains(d) ||
          _worksAny(id, d + 1) ||
          _has24(id, d - 1) ||
          _breaks24Chain(id, d)) {
        return false;
      }
    }
    for (final d in _w16[id]!) {
      if (!available[id]!.contains(d) || _has24(id, d - 1)) return false;
    }
    return true;
  }

  bool _trySwap(
    String a,
    int d1,
    String b,
    int d2, {
    required bool is16b,
    required double current,
  }) {
    if (is16b) {
      _remove16(d1);
      _remove16(d2);
      if (_canPlace16(b, d1) && _canPlace16(a, d2)) {
        _place16(b, d1);
        _place16(a, d2);
        if (_score() < current - 1e-9) return true;
        _remove16(d1);
        _remove16(d2);
      }
      _place16(a, d1);
      _place16(b, d2);
    } else {
      _remove24(d1);
      _remove24(d2);
      if (_canPlace24(b, d1) && _canPlace24(a, d2)) {
        _place24(b, d1);
        _place24(a, d2);
        if (_score() < current - 1e-9) return true;
        _remove24(d1);
        _remove24(d2);
      }
      _place24(a, d1);
      _place24(b, d2);
    }
    return false;
  }

  RosterIssue describeGap(int d, {required bool is16b, required int month}) {
    const role = Role.radiologyTech;
    final label = is16b ? '16B teknikeri' : '24 teknikeri';
    if (members.isEmpty) {
      return RosterIssue(
        day: d,
        role: role,
        missing: 1,
        message:
            '${formatDayMonth(d, month)}: $label eksik. Hiç aktif radyoloji '
            'teknikeri yok.',
      );
    }
    String date(int day) => day >= 1
        ? formatDayMonth(day, month)
        : 'önceki ayın ${day == 0 ? 'son günü' : '${1 - day}. son günü'}';
    final reasons = <String>[];
    for (final p in [
      ...members,
    ]..sort((a, b) => compareTurkish(a.name, b.name))) {
      final id = p.id;
      if (_slot24[d] == id || _slot16[d] == id) continue;
      final String? reason;
      if (!available[id]!.contains(d)) {
        reason = 'istemiyor';
      } else if (_has24(id, d - 1)) {
        reason = '${date(d - 1)} 24 nöbetçi (ertesi gün çalışamaz)';
      } else if (!is16b && _worksAny(id, d + 1)) {
        reason = '${date(d + 1)} nöbetçi (24 sonrası boş gün)';
      } else if (!is16b && _breaks24Chain(id, d)) {
        reason = 'gün aşırı zincir sınırında';
      } else if (_slot24[d] == id || _slot16[d] == id) {
        reason = null;
      } else {
        reason = 'uygun değil';
      }
      if (reason != null) reasons.add('${p.name} $reason');
    }
    return RosterIssue(
      day: d,
      role: role,
      missing: 1,
      message:
          '${formatDayMonth(d, month)}: $label eksik. ${reasons.join('; ')}.',
    );
  }
}
