import 'package:collection/collection.dart';

import 'day_assignment.dart';

/// İzin türü: yıllık izin, şua (radyasyon) izni ve sağlık raporu. Hepsi
/// nöbet verilmesini engeller ve kişinin gereken saatinden düşülür; listede
/// farklı renk ve kısaltmayla gösterilir. Yıllık izin öncesi/sonrası iş günü
/// kuralları yalnızca yıllık izne uygulanır.
enum LeaveType {
  annual('Yıllık izin', 'Y.İ.'),
  radiation('Şua izni', 'Ş.İ.'),
  sick('Rapor', 'R.');

  const LeaveType(this.label, this.shortLabel);

  /// Tam ad ("Yıllık izin").
  final String label;

  /// Tablo/PDF hücresindeki kısaltma ("Y.İ.").
  final String shortLabel;
}

/// Bir ayın planı: istenmeyen günler ve oluşturulan nöbet listesi.
class MonthPlan {
  const MonthPlan({
    required this.year,
    required this.month,
    this.unavailableDays = const {},
    this.assignments = const {},
    this.generatedAt,
    this.isLocked = false,
    this.seed,
    this.nurseOnly = false,
    this.overtimeRequests = const {},
    this.annualLeave = const {},
    this.radiationLeave = const {},
    this.sickLeave = const {},
    this.requestedShifts = const {},
    this.dayShiftOverrides = const {},
    this.handovers = const {},
  });

  final int year;

  /// 1..12
  final int month;

  /// Kişi kimliği → o kişinin nöbet istemediği günler (ayın günleri).
  final Map<String, List<int>> unavailableDays;

  /// Ayın günü → o günün nöbetçileri. Liste oluşturulmadıysa boş.
  final Map<int, DayAssignment> assignments;

  /// Listenin en son oluşturulduğu an; hiç oluşturulmadıysa boş.
  final DateTime? generatedAt;

  /// Kilitli ay yanlışlıkla yeniden oluşturulamaz.
  final bool isLocked;

  /// Listeyi üreten tohum; aynı girdilerle aynı liste yeniden üretilebilir.
  final int? seed;

  /// Bu ay yalnız hemşire listesi olarak oluşturuldu (tekniker yok).
  final bool nurseOnly;

  /// Bu ay fazla mesai isteyen kişiler; nöbet sayıları diğerlerinden birkaç
  /// fazla olabilir.
  final Set<String> overtimeRequests;

  /// Kişi bu ay fazla mesai istiyor mu?
  bool wantsOvertime(String personId) => overtimeRequests.contains(personId);

  /// Kişi kimliği → o kişinin yıllık izinli olduğu günler. İzin günü hem
  /// nöbet verilmesini engeller hem de kişinin gereken saatinden düşülür.
  final Map<String, List<int>> annualLeave;

  /// Kişi kimliği → o kişinin şua (radyasyon) izinli olduğu günler. Yıllık
  /// izinle aynı davranır: nöbet engellenir ve gereken saatten düşülür.
  final Map<String, List<int>> radiationLeave;

  /// Kişi kimliği → o kişinin sağlık raporlu olduğu günler. Şua izni gibi
  /// davranır: nöbet engellenir ve gereken saatten düşülür.
  final Map<String, List<int>> sickLeave;

  /// Kişi kimliği → o kişinin mutlaka nöbet tutacağı günler (sorumlu
  /// hemşire için seçilir). Liste oluşturulurken bu günlere sabit yazılır.
  final Map<String, List<int>> requestedShifts;

  /// Gün → 7A'ya elle yazılan kişi. Otomatik seçimin (sorumlu hemşire ya da
  /// yerine geçen) yerine geçer. Liste yeniden oluşturulunca temizlenir.
  final Map<int, String> dayShiftOverrides;

  /// Pasif yapılan kişinin başkasına devredilen nöbetleri:
  /// `"kişi:gün"` → devralan kişi ("" ise kimseye verilemedi, koltuk boş
  /// kaldı). Pasif dönemi kısalırsa ya da sonlandırılırsa geri vermek için.
  final Map<String, String> handovers;

  static String handoverKey(String personId, int day) => '$personId:$day';

  /// Kişinin devredilen nöbetleri: gün → devralan ("" ise boş kaldı).
  Map<int, String> handoversOf(String personId) => {
    for (final e in handovers.entries)
      if (e.key.startsWith('$personId:'))
        int.parse(e.key.substring(personId.length + 1)): e.value,
  };

  /// Kişinin seçilmiş nöbet günleri.
  List<int> requestedShiftsOf(String personId) =>
      requestedShifts[personId] ?? const [];

  /// Kişinin yıllık izin günleri.
  List<int> annualLeaveOf(String personId) => annualLeave[personId] ?? const [];

  /// Kişinin şua izni günleri.
  List<int> radiationLeaveOf(String personId) =>
      radiationLeave[personId] ?? const [];

  /// Kişinin rapor günleri.
  List<int> sickLeaveOf(String personId) => sickLeave[personId] ?? const [];

  /// Türün kişi → gün haritası.
  Map<String, List<int>> leaveMap(LeaveType type) => switch (type) {
    LeaveType.annual => annualLeave,
    LeaveType.radiation => radiationLeave,
    LeaveType.sick => sickLeave,
  };

  /// Kişinin verilen türdeki izin günleri.
  List<int> leaveOf(String personId, LeaveType type) =>
      leaveMap(type)[personId] ?? const [];

  /// Kişinin tüm izin günleri (yıllık + şua + rapor), tekilleşmiş ve sıralı.
  List<int> leaveDaysOf(String personId) => ({
    for (final type in LeaveType.values) ...leaveOf(personId, type),
  }.toList()..sort());

  /// Kişi kimliği → tüm izin günleri. Gereken saat düşümü için.
  Map<String, List<int>> get leaveDays {
    final ids = {for (final type in LeaveType.values) ...leaveMap(type).keys};
    return {for (final id in ids) id: leaveDaysOf(id)};
  }

  /// Nöbet dağıtımında engellenen günler: istenmeyen günler + tüm izinler.
  Map<String, List<int>> get blockedDays {
    final ids = {
      ...unavailableDays.keys,
      for (final type in LeaveType.values) ...leaveMap(type).keys,
    };
    return {
      for (final id in ids)
        id: {...unavailableDaysOf(id), ...leaveDaysOf(id)}.toList()..sort(),
    };
  }

  /// Nöbet listesi oluşturulmuş mu?
  bool get hasRoster => assignments.isNotEmpty;

  /// Kişi istekleri (istenmeyen günler, istenen nöbet günleri, fazla mesai)
  /// girilmiş mi? İzinler istek sayılmaz.
  bool get hasPersonRequests =>
      unavailableDays.values.any((d) => d.isNotEmpty) ||
      requestedShifts.values.any((d) => d.isNotEmpty) ||
      overtimeRequests.isNotEmpty;

  /// Kişi isteklerinin kısa dökümü, satır satır ("• 3 kişi: 7 istenmeyen
  /// gün"); yoksa boş metin.
  String get personRequestSummary {
    String line(Map<String, List<int>> map, String what) {
      final people = map.values.where((d) => d.isNotEmpty);
      final days = people.fold(0, (s, d) => s + d.length);
      return '• ${people.length} kişi: $days $what';
    }

    return [
      if (unavailableDays.values.any((d) => d.isNotEmpty))
        line(unavailableDays, 'istenmeyen gün'),
      if (requestedShifts.values.any((d) => d.isNotEmpty))
        line(requestedShifts, 'seçilen nöbet günü'),
      if (overtimeRequests.isNotEmpty)
        '• ${overtimeRequests.length} kişi: fazla mesai isteği',
    ].join('\n');
  }

  /// Saklama anahtarı: `yyyy-MM`.
  String get key => keyFor(year, month);

  static String keyFor(int year, int month) =>
      '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}';

  /// Ayın gün sayısı.
  int get daysInMonth => DateTime(year, month + 1, 0).day;

  /// Kişinin istemediği günler.
  List<int> unavailableDaysOf(String personId) =>
      unavailableDays[personId] ?? const [];

  /// Kişi bu ayın listesinde ya da istenmeyen günlerinde geçiyor mu?
  bool references(String personId) =>
      unavailableDays.containsKey(personId) ||
      annualLeave.containsKey(personId) ||
      radiationLeave.containsKey(personId) ||
      sickLeave.containsKey(personId) ||
      requestedShifts.containsKey(personId) ||
      assignments.values.any((a) => a.includes(personId));

  MonthPlan copyWith({
    Map<String, List<int>>? unavailableDays,
    Map<int, DayAssignment>? assignments,
    DateTime? generatedAt,
    bool? isLocked,
    int? seed,
    bool? nurseOnly,
    Set<String>? overtimeRequests,
    Map<String, List<int>>? annualLeave,
    Map<String, List<int>>? radiationLeave,
    Map<String, List<int>>? sickLeave,
    Map<String, List<int>>? requestedShifts,
    Map<int, String>? dayShiftOverrides,
    Map<String, String>? handovers,
  }) {
    return MonthPlan(
      year: year,
      month: month,
      unavailableDays: unavailableDays ?? this.unavailableDays,
      assignments: assignments ?? this.assignments,
      generatedAt: generatedAt ?? this.generatedAt,
      isLocked: isLocked ?? this.isLocked,
      seed: seed ?? this.seed,
      nurseOnly: nurseOnly ?? this.nurseOnly,
      overtimeRequests: overtimeRequests ?? this.overtimeRequests,
      annualLeave: annualLeave ?? this.annualLeave,
      radiationLeave: radiationLeave ?? this.radiationLeave,
      sickLeave: sickLeave ?? this.sickLeave,
      requestedShifts: requestedShifts ?? this.requestedShifts,
      dayShiftOverrides: dayShiftOverrides ?? this.dayShiftOverrides,
      handovers: handovers ?? this.handovers,
    );
  }

  Map<String, dynamic> toJson() => {
    'year': year,
    'month': month,
    'unavailableDays': unavailableDays,
    // JSON anahtarları metin olmak zorunda.
    'assignments': {
      for (final e in assignments.entries) '${e.key}': e.value.toJson(),
    },
    'generatedAt': generatedAt?.toIso8601String(),
    'isLocked': isLocked,
    'seed': seed,
    'nurseOnly': nurseOnly,
    'overtimeRequests': overtimeRequests.toList(),
    'annualLeave': annualLeave,
    'radiationLeave': radiationLeave,
    'sickLeave': sickLeave,
    'requestedShifts': requestedShifts,
    'dayShiftOverrides': {
      for (final e in dayShiftOverrides.entries) '${e.key}': e.value,
    },
    'handovers': handovers,
  };

  factory MonthPlan.fromJson(Map<String, dynamic> json) {
    final unavailable = json['unavailableDays'] as Map? ?? const {};
    final assignments = json['assignments'] as Map? ?? const {};
    final generatedAt = json['generatedAt'] as String?;
    return MonthPlan(
      year: json['year'] as int,
      month: json['month'] as int,
      unavailableDays: {
        for (final e in unavailable.entries)
          e.key as String: (e.value as List).cast<int>(),
      },
      assignments: {
        for (final e in assignments.entries)
          int.parse(e.key as String): DayAssignment.fromJson(
            (e.value as Map).cast<String, dynamic>(),
          ),
      },
      generatedAt: generatedAt == null ? null : DateTime.parse(generatedAt),
      isLocked: json['isLocked'] as bool? ?? false,
      seed: json['seed'] as int?,
      nurseOnly: json['nurseOnly'] as bool? ?? false,
      overtimeRequests: {
        ...?(json['overtimeRequests'] as List?)?.cast<String>(),
      },
      annualLeave: {
        for (final e in (json['annualLeave'] as Map? ?? const {}).entries)
          e.key as String: (e.value as List).cast<int>(),
      },
      radiationLeave: {
        for (final e in (json['radiationLeave'] as Map? ?? const {}).entries)
          e.key as String: (e.value as List).cast<int>(),
      },
      sickLeave: {
        for (final e in (json['sickLeave'] as Map? ?? const {}).entries)
          e.key as String: (e.value as List).cast<int>(),
      },
      requestedShifts: {
        for (final e in (json['requestedShifts'] as Map? ?? const {}).entries)
          e.key as String: (e.value as List).cast<int>(),
      },
      dayShiftOverrides: {
        for (final e in (json['dayShiftOverrides'] as Map? ?? const {}).entries)
          int.parse(e.key as String): e.value as String,
      },
      handovers: {
        for (final e in (json['handovers'] as Map? ?? const {}).entries)
          e.key as String: e.value as String,
      },
    );
  }

  static const _unavailableEquality = MapEquality<String, List<int>>(
    values: ListEquality<int>(),
  );
  static const _assignmentsEquality = MapEquality<int, DayAssignment>();

  @override
  bool operator ==(Object other) =>
      other is MonthPlan &&
      other.year == year &&
      other.month == month &&
      _unavailableEquality.equals(other.unavailableDays, unavailableDays) &&
      _assignmentsEquality.equals(other.assignments, assignments) &&
      other.generatedAt == generatedAt &&
      other.isLocked == isLocked &&
      other.seed == seed &&
      other.nurseOnly == nurseOnly &&
      const SetEquality<String>().equals(
        other.overtimeRequests,
        overtimeRequests,
      ) &&
      _unavailableEquality.equals(other.annualLeave, annualLeave) &&
      _unavailableEquality.equals(other.radiationLeave, radiationLeave) &&
      _unavailableEquality.equals(other.sickLeave, sickLeave) &&
      _unavailableEquality.equals(other.requestedShifts, requestedShifts) &&
      const MapEquality<int, String>().equals(
        other.dayShiftOverrides,
        dayShiftOverrides,
      ) &&
      const MapEquality<String, String>().equals(other.handovers, handovers);

  @override
  int get hashCode => Object.hash(
    year,
    month,
    _unavailableEquality.hash(unavailableDays),
    _assignmentsEquality.hash(assignments),
    generatedAt,
    isLocked,
    seed,
    nurseOnly,
    const SetEquality<String>().hash(overtimeRequests),
    _unavailableEquality.hash(annualLeave),
    _unavailableEquality.hash(radiationLeave),
    _unavailableEquality.hash(sickLeave),
    _unavailableEquality.hash(requestedShifts),
    const MapEquality<int, String>().hash(dayShiftOverrides),
    const MapEquality<String, String>().hash(handovers),
  );

  @override
  String toString() => 'MonthPlan($key, ${assignments.length} gün atanmış)';
}
