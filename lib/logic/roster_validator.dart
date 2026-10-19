import 'dart:math';

import '../models/day_assignment.dart';
import 'block_reason.dart';
import 'shift_gaps.dart';
import '../models/person.dart';
import '../models/role.dart';
import '../models/roster_settings.dart';
import 'turkish_collation.dart';
import 'turkish_dates.dart';

/// Kural ihlalinin türü.
enum ViolationKind {
  /// O gün o rolde koltuk boş.
  missing,

  /// Kişi nöbet yazılamayan güne (istemediği gün, izin, izin öncesi/sonrası,
  /// pasif) atanmış; nedeni mesajda yazar.
  unavailable,

  /// Kişi art arda iki gün nöbette.
  consecutive,

  /// Gün aşırı zincir sınırı aşılmış (ör. 3-5-7).
  chain,

  /// Fazla nöbet sınırı (grup ortalaması + N) aşılmış.
  overCap,

  /// Kişi kendi görevi olmayan koltukta (ör. tekniker hemşire satırında).
  wrongRole,

  /// Sorumlu hemşire seçmediği bir güne nöbete yazılmış.
  chargeNurseUnrequested,

  /// İki nöbet arasındaki boşluk önerilen en fazla günü aşıyor.
  longGap,

  /// 5 günlük boşluklar rol grubunda herkese eşit sayıda düşmemiş.
  unevenFiveGaps,

  /// Güne gerekenden fazla hemşire yazılmış (serbest düzenleme).
  overStaffed,

  /// Şua izninden dönen kişi ilk iş gününde nöbette değil.
  radiationReturn,
}

/// Bir kural ihlali.
class RuleViolation {
  const RuleViolation({
    required this.kind,
    required this.days,
    required this.message,
    this.personId,
    this.role,
    this.detail,
  });

  final ViolationKind kind;

  /// İlgili günler (bu ayın günleri; önceki aya ait günler yer almaz).
  final List<int> days;

  /// İlgili kişi (eksik koltukta boş).
  final String? personId;
  final Role? role;

  /// Türkçe açıklama, ör. "Mehmet 14 ve 15 Ekim art arda nöbette."
  final String message;

  /// Boş koltukta: o rolden her kişinin o güne neden yazılamadığı, satır
  /// satır ("Ali: 15 Ekim nöbetçi (art arda gün)").
  final String? detail;

  @override
  String toString() => message;
}

/// Bir ay listesini kurallara göre denetler (saf Dart). Elle düzenlemeden
/// sonra ihlalleri göstermek için kullanılır; ihlale izin verilir ama
/// uyarı kalır.
class RosterValidator {
  const RosterValidator(this.settings);

  final RosterSettings settings;

  List<RuleViolation> validate({
    required int year,
    required int month,
    required Map<int, DayAssignment> assignments,
    required Iterable<Person> people,
    Map<String, List<int>> unavailableDays = const {},
    Map<String, Map<int, BlockReason>> blockReasons = const {},
    List<Set<String>> previousMonthTail = const [],
    Set<String> overtimeRequests = const {},
    int overtimeAllowance = 2,
    Map<String, List<int>> requestedShifts = const {},
    Map<String, Set<int>> radiationReturnDays = const {},
    Map<String, List<int>> absentDays = const {},
  }) {
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final byId = {for (final p in people) p.id: p};
    String name(String id) => byId[id]?.name ?? 'Silinmiş kişi';
    String date(int d) => d >= 1
        ? formatDayMonth(d, month)
        : d == 0
        ? 'önceki ayın son günü'
        : 'önceki ayın ${1 - d}. son günü';

    final violations = <RuleViolation>[];

    // Kişi → nöbet günleri (önceki ay: 0, -1, ...), kişi → atandığı rol.
    // blocking24: 24 saat (ağır) vardiyalar — ertesi gün çalışmayı engeller ve
    // gün aşırı zinciri bunlar üzerinden sayılır. 16B günleri worked'tedir ama
    // blocking24'te değildir. Önceki ay kuyruğu 24 kabul edilir.
    final worked = <String, Set<int>>{};
    final blocking24 = <String, Set<int>>{};
    for (var i = 0; i < previousMonthTail.length; i++) {
      final offset = i - (previousMonthTail.length - 1);
      for (final id in previousMonthTail[i]) {
        (worked[id] ??= {}).add(offset);
        (blocking24[id] ??= {}).add(offset);
      }
    }
    final seatRole = <String, Role>{};

    for (var d = 1; d <= daysInMonth; d++) {
      final a = assignments[d] ?? DayAssignment(day: d);
      final seats = [
        for (final id in a.nurseIds) (id, Role.nurse, false),
        if (a.techId != null) (a.techId!, Role.radiologyTech, false),
        if (a.tech16bId != null) (a.tech16bId!, Role.radiologyTech, true),
      ];
      for (final (id, role, light) in seats) {
        if (!light) (blocking24[id] ??= {}).add(d);
        (worked[id] ??= {}).add(d);
        seatRole[id] = role;
        final person = byId[id];
        if (person != null && person.role != role) {
          violations.add(
            RuleViolation(
              kind: ViolationKind.wrongRole,
              days: [d],
              personId: id,
              role: role,
              message:
                  '${person.name} ${person.role.label} ama ${date(d)} '
                  '${turkishLowerCase(role.label)} koltuğunda.',
            ),
          );
        }
        if ((unavailableDays[id] ?? const []).contains(d)) {
          violations.add(
            RuleViolation(
              kind: ViolationKind.unavailable,
              days: [d],
              personId: id,
              role: role,
              // Neden bilinmiyorsa istemediği gün sayılır.
              message: (blockReasons[id]?[d] ?? BlockReason.unavailable)
                  .message(name(id), date(d)),
            ),
          );
        }
        if ((person?.isChargeNurse ?? false) &&
            !(requestedShifts[id]?.contains(d) ?? false)) {
          violations.add(
            RuleViolation(
              kind: ViolationKind.chargeNurseUnrequested,
              days: [d],
              personId: id,
              role: role,
              message:
                  'Sorumlu hemşire ${name(id)} seçmediği güne (${date(d)}) '
                  'nöbete yazıldı.',
            ),
          );
        }
      }

      final missingNurses = max(0, settings.nursesPerDay - a.nurseIds.length);
      if (missingNurses > 0) {
        violations.add(
          RuleViolation(
            kind: ViolationKind.missing,
            days: [d],
            role: Role.nurse,
            message:
                '${date(d)}: $missingNurses ${turkishLowerCase(Role.nurse.label)} eksik.',
          ),
        );
      }
      final extraNurses = a.nurseIds.length - settings.nursesPerDay;
      if (extraNurses > 0) {
        violations.add(
          RuleViolation(
            kind: ViolationKind.overStaffed,
            days: [d],
            role: Role.nurse,
            message:
                '${date(d)}: $extraNurses fazla '
                '${turkishLowerCase(Role.nurse.label)} yazılı.',
          ),
        );
      }
      // Tek tekniker: 24 koltuğu; iki tekniker: 24 + 16B koltukları.
      if (settings.techsPerDay >= 1 && a.techId == null) {
        final label = settings.techsPerDay >= 2
            ? '24 teknikeri'
            : '1 ${turkishLowerCase(Role.radiologyTech.label)}';
        violations.add(
          RuleViolation(
            kind: ViolationKind.missing,
            days: [d],
            role: Role.radiologyTech,
            message: '${date(d)}: $label eksik.',
          ),
        );
      }
      if (settings.techsPerDay >= 2 && a.tech16bId == null) {
        violations.add(
          RuleViolation(
            kind: ViolationKind.missing,
            days: [d],
            role: Role.radiologyTech,
            message: '${date(d)}: 16B teknikeri eksik.',
          ),
        );
      }
    }

    final chainLimit = max(1, settings.maxEveryOtherDayChain);

    // Boş koltuklar: o rolden her kişinin o güne neden yazılamadığı.
    String? gapDetail(int d, Role role) {
      final lines = <String>[];
      final members =
          byId.values
              .where((p) => p.role == role && p.worksInMonth(year, month))
              .toList()
            ..sort((a, b) => compareTurkish(a.name, b.name));
      final strict =
          settings.forbidConsecutiveDays ||
          (role == Role.radiologyTech && settings.techsPerDay >= 2);
      for (final p in members) {
        final id = p.id;
        if (assignments[d]?.includes(id) ?? false) continue;
        final heavy = blocking24[id] ?? const <int>{};
        final days = worked[id] ?? const <int>{};
        final reasons = <String>[
          if (unavailableDays[id]?.contains(d) ?? false)
            (blockReasons[id]?[d] ?? BlockReason.unavailable).label,
          if (p.isChargeNurse && !(requestedShifts[id]?.contains(d) ?? false))
            'sorumlu hemşire, bu günü seçmedi',
          if (strict && heavy.contains(d - 1))
            '${date(d - 1)} nöbetçi (art arda gün)',
          if (strict && days.contains(d + 1))
            '${formatDayMonth(d + 1, month)} nöbetçi (art arda gün)',
        ];
        // Bu güne yazılsa gün aşırı zincir sınırı aşılır mı?
        var first = d;
        while (heavy.contains(first - 2)) {
          first -= 2;
        }
        var last = d;
        while (heavy.contains(last + 2)) {
          last += 2;
        }
        if ((last - first) ~/ 2 + 1 > chainLimit) {
          final chain = [
            for (var x = first; x <= last; x += 2) x >= 1 ? '$x' : date(x),
          ];
          reasons.add('${chain.join('-')} gün aşırı zincir olur');
        }
        lines.add(
          reasons.isEmpty
              ? '${p.name}: kurallara uyuyor, elle eklenebilir'
              : '${p.name}: ${reasons.join(', ')}',
        );
      }
      return lines.isEmpty ? null : lines.join('\n');
    }

    for (var i = 0; i < violations.length; i++) {
      final v = violations[i];
      if (v.kind != ViolationKind.missing || v.role == null) continue;
      violations[i] = RuleViolation(
        kind: v.kind,
        days: v.days,
        role: v.role,
        message: v.message,
        detail: gapDetail(v.days.single, v.role!),
      );
    }

    final ids = worked.keys.toList()
      ..sort((a, b) => compareTurkish(name(a), name(b)));
    for (final id in ids) {
      final days = worked[id]!;
      final heavy = blocking24[id] ?? const <int>{};
      final role = seatRole[id] ?? byId[id]?.role;
      if (!days.any((d) => d >= 1)) continue; // yalnız önceki ayda

      // 24 vardiyası ertesi gün çalışmayı engeller. Teknikerde iki vardiya
      // varken bu her zaman geçerli (16B hariç); hemşirede ve tek teknikerde
      // ayardaki art arda gün yasağına bağlı.
      final techSplit = settings.techsPerDay >= 2 && role == Role.radiologyTech;
      final strictNextDay = techSplit || settings.forbidConsecutiveDays;
      if (strictNextDay) {
        for (final d in heavy.toList()..sort()) {
          if (d + 1 > daysInMonth || !days.contains(d + 1)) continue;
          violations.add(
            RuleViolation(
              kind: ViolationKind.consecutive,
              days: [if (d >= 1) d, d + 1],
              personId: id,
              role: role,
              message: d >= 1
                  ? '${name(id)} $d ve ${formatDayMonth(d + 1, month)} '
                        'art arda nöbette.'
                  : '${name(id)} ${date(d)} ve ${date(d + 1)} '
                        'art arda nöbette.',
            ),
          );
        }
      }

      // Nöbetler arası boşluk (araya izin / pasif gün girmeyenler).
      final off = {
        ...?absentDays[id],
        ...?byId[id]?.inactiveDaysIn(year, month),
      };
      for (final (a, b, gap) in ShiftGaps.gaps(
        days,
        absent: off,
        monthEnd: daysInMonth,
      )) {
        if (gap <= ShiftGaps.maxGap || (byId[id]?.isChargeNurse ?? false)) {
          continue;
        }
        final from = a >= 1 ? '$a' : date(a);
        violations.add(
          RuleViolation(
            kind: ViolationKind.longGap,
            days: [if (a >= 1) a, if (b <= daysInMonth) b],
            personId: id,
            role: role,
            message: b > daysInMonth
                ? '${name(id)} son nöbeti ${a >= 1 ? formatDayMonth(a, month) : from}; '
                      'ay sonuna kadar $gap gün boş '
                      '(en fazla ${ShiftGaps.maxGap}).'
                : '${name(id)} $from ve '
                      '${formatDayMonth(b, month)} arasında $gap gün boş '
                      '(en fazla ${ShiftGaps.maxGap}).',
          ),
        );
      }

      // Gün aşırı zincirler yalnız 24 vardiyalarında: d, d+2, d+4, ...
      for (final start in heavy.toList()..sort()) {
        if (heavy.contains(start - 2)) continue; // zincirin başı değil
        final chain = [start];
        while (heavy.contains(chain.last + 2)) {
          chain.add(chain.last + 2);
        }
        if (chain.length <= chainLimit || !chain.any((d) => d >= 1)) {
          continue;
        }
        final inMonth = chain.where((d) => d >= 1).toList();
        final labels = chain.map((d) => d >= 1 ? '$d' : date(d)).toList();
        final listed =
            '${labels.sublist(0, labels.length - 1).join(', ')} ve '
            '${labels.last} ${turkishMonthNames[month - 1]}';
        violations.add(
          RuleViolation(
            kind: ViolationKind.chain,
            days: inMonth,
            personId: id,
            role: role,
            message:
                '${name(id)} $listed gün aşırı nöbette '
                '(en fazla $chainLimit olabilir).',
          ),
        );
      }
    }

    // 5 günlük boşluk ya herkese eşit sayıda düşer ya da hiç kimseye.
    for (final role in Role.values) {
      final members =
          byId.values
              .where(
                (p) =>
                    p.role == role &&
                    !p.isChargeNurse &&
                    p.worksInMonth(year, month),
              )
              .toList()
            ..sort((a, b) => compareTurkish(a.name, b.name));
      if (members.length < 2) continue;
      final fives = {
        for (final p in members)
          p.id: ShiftGaps.maxGapCount(
            worked[p.id] ?? const <int>{},
            absent: {...?absentDays[p.id], ...p.inactiveDaysIn(year, month)},
          ),
      };
      if (ShiftGaps.unevenMaxGaps(fives.values) == 0) continue;
      final low = fives.values.reduce(min);
      final more = [
        for (final p in members)
          if (fives[p.id]! > low) '${p.name} ${fives[p.id]}',
      ];
      violations.add(
        RuleViolation(
          kind: ViolationKind.unevenFiveGaps,
          days: const [],
          role: role,
          message:
              '${role.pluralLabel}: 5 günlük boşluk herkese eşit düşmedi '
              '(${more.join(', ')}; diğerleri $low).',
        ),
      );
    }

    final extra = settings.maxExtraOverAverage;
    if (extra != null) {
      for (final role in Role.values) {
        final perDay = role == Role.nurse
            ? settings.nursesPerDay
            : settings.techsPerDay;
        // Sorumlu hemşire nöbet dengesine girmez.
        final members = byId.values.where(
          (p) =>
              p.worksInMonth(year, month) && p.role == role && !p.isChargeNurse,
        );
        if (members.isEmpty || perDay == 0) continue;
        final baseCap = (daysInMonth * perDay / members.length).ceil() + extra;
        for (final id in ids) {
          if (seatRole[id] != role) continue;
          if (byId[id]?.isChargeNurse ?? false) continue;
          // Fazla mesai isteyene ek pay tanınır.
          final cap =
              baseCap + (overtimeRequests.contains(id) ? overtimeAllowance : 0);
          final inMonth = worked[id]!.where((d) => d >= 1).toList()..sort();
          if (inMonth.length <= cap) continue;
          violations.add(
            RuleViolation(
              kind: ViolationKind.overCap,
              days: inMonth,
              personId: id,
              role: role,
              message:
                  '${name(id)} ${inMonth.length} nöbet tutuyor; sınır $cap '
                  '(grup ortalaması + $extra).',
            ),
          );
        }
      }
    }

    // Şua dönüşünün ilk iş günü mutlaka nöbet (istemediği gün değilse).
    for (final MapEntry(key: id, value: returnDays)
        in radiationReturnDays.entries) {
      final person = byId[id];
      if (person == null || !person.worksInMonth(year, month)) continue;
      if (person.role == Role.radiologyTech && settings.techsPerDay == 0) {
        continue; // yalnız hemşire ayı
      }
      for (final d in returnDays.toList()..sort()) {
        if (d < 1 || d > daysInMonth) continue;
        if (worked[id]?.contains(d) ?? false) continue;
        if (unavailableDays[id]?.contains(d) ?? false) continue;
        violations.add(
          RuleViolation(
            kind: ViolationKind.radiationReturn,
            days: [d],
            personId: id,
            role: person.role,
            message:
                '${name(id)} şua izninden dönüşün ilk iş günü '
                '(${date(d)}) nöbete yazılmadı.',
          ),
        );
      }
    }

    violations.sort((a, b) {
      final c = (a.days.firstOrNull ?? 0).compareTo(b.days.firstOrNull ?? 0);
      if (c != 0) return c;
      final k = a.kind.index.compareTo(b.kind.index);
      if (k != 0) return k;
      final r = (a.role?.index ?? -1).compareTo(b.role?.index ?? -1);
      return r != 0 ? r : a.message.compareTo(b.message);
    });
    return violations;
  }
}
