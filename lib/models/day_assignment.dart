import 'package:collection/collection.dart';

/// Ayın bir gününün nöbetçileri.
class DayAssignment {
  const DayAssignment({
    required this.day,
    this.nurseIds = const [],
    this.techId,
    this.tech16bId,
    this.shift16aIds = const [],
    this.customShifts = const {},
    this.extraShifts = const {},
  });

  /// Ayın günü (1..31).
  final int day;

  /// Nöbetçi hemşirelerin kimlikleri (normalde 2 kişi).
  final List<String> nurseIds;

  /// 24 saat nöbet tutan radyoloji teknikeri; henüz atanmadıysa boş.
  final String? techId;

  /// 16B (16 saat) vardiyasındaki radyoloji teknikeri; yalnızca günde 2
  /// tekniker tutulan aylarda dolar. 16B çalışan ertesi gün çalışabilir.
  final String? tech16bId;

  /// 16A (16:00–08:00) vardiyasındakiler: [nurseIds] içinden hemşireler ve
  /// 24 koltuğundaki tekniker ([techId]); elle yazılır. Koltuğu doldurur,
  /// kurallarda nöbet sayılır, 16 saat.
  final List<String> shift16aIds;

  /// Koltuktaki kişi → özel mesai adı ([CustomShift.fillsSeat] açık olan,
  /// ör. "19A"). Hemşire koltuğu ya da teknikerin 24 koltuğu; 16A gibi
  /// koltuğun özelliğidir.
  final Map<String, String> customShifts;

  /// Koltukta olmayan kişi → ek özel mesai adı (koltuk doldurmayan özel
  /// mesai; kurallarda nöbet sayılmaz).
  final Map<String, String> extraShifts;

  /// 16A vardiyasının saati.
  static const shift16aHours = 16;

  /// Bu günde nöbet tutan herkes.
  List<String> get personIds => [...nurseIds, ?techId, ?tech16bId];

  bool includes(String personId) => personIds.contains(personId);

  /// [personId] bu gün 16B vardiyasında mı? (Değilse 24 kabul edilir.)
  bool isSecondaryTech(String personId) => personId == tech16bId;

  /// [personId] bu gün 16A vardiyasında mı (hemşire ya da 24 koltuğundaki
  /// tekniker)?
  bool is16a(String personId) =>
      shift16aIds.contains(personId) &&
      (nurseIds.contains(personId) || techId == personId);

  /// [personId] koltukta mı (hemşire ya da teknikerin 24 koltuğu)?
  bool _inMainSeat(String personId) =>
      nurseIds.contains(personId) || techId == personId;

  /// Koltuktaki kişinin özel mesaisi (ör. "19A"); yoksa null.
  String? customShiftOf(String personId) =>
      _inMainSeat(personId) ? customShifts[personId] : null;

  /// Koltukta olmayan kişinin ek özel mesaisi; yoksa null.
  String? extraShiftOf(String personId) =>
      includes(personId) ? null : extraShifts[personId];

  /// Kişinin bu günkü vardiyası: "16B", "16A", özel mesai adı ya da "24".
  String shiftCode(String personId) => isSecondaryTech(personId)
      ? '16B'
      : is16a(personId)
      ? '16A'
      : customShiftOf(personId) ?? '24';

  DayAssignment copyWith({
    List<String>? nurseIds,
    String? techId,
    bool clearTech = false,
    String? tech16bId,
    bool clearTech16b = false,
    List<String>? shift16aIds,
    Map<String, String>? customShifts,
    Map<String, String>? extraShifts,
  }) {
    final nurses = nurseIds ?? this.nurseIds;
    final tech = clearTech ? null : (techId ?? this.techId);
    return DayAssignment(
      day: day,
      nurseIds: nurses,
      techId: tech,
      tech16bId: clearTech16b ? null : (tech16bId ?? this.tech16bId),
      // Günden (ya da 24 koltuğundan) çıkanın 16A işareti düşer.
      shift16aIds: [
        for (final id in shift16aIds ?? this.shift16aIds)
          if (nurses.contains(id) || id == tech) id,
      ],
      customShifts: {
        for (final e in (customShifts ?? this.customShifts).entries)
          if (nurses.contains(e.key) || e.key == tech) e.key: e.value,
      },
      // Koltuğa yazılanın ek mesaisi düşer.
      extraShifts: {
        for (final e in (extraShifts ?? this.extraShifts).entries)
          if (!nurses.contains(e.key) &&
              e.key != tech &&
              e.key != (clearTech16b ? null : (tech16bId ?? this.tech16bId)))
            e.key: e.value,
      },
    );
  }

  Map<String, dynamic> toJson() => {
    'day': day,
    'nurseIds': nurseIds,
    'techId': techId,
    'tech16bId': tech16bId,
    if (shift16aIds.isNotEmpty) 'nurse16aIds': shift16aIds,
    if (customShifts.isNotEmpty) 'customShifts': customShifts,
    if (extraShifts.isNotEmpty) 'extraShifts': extraShifts,
  };

  factory DayAssignment.fromJson(Map<String, dynamic> json) => DayAssignment(
    day: json['day'] as int,
    nurseIds: (json['nurseIds'] as List? ?? const []).cast<String>(),
    techId: json['techId'] as String?,
    tech16bId: json['tech16bId'] as String?,
    shift16aIds: (json['nurse16aIds'] as List? ?? const []).cast<String>(),
    customShifts: (json['customShifts'] as Map? ?? const {})
        .cast<String, String>(),
    extraShifts: (json['extraShifts'] as Map? ?? const {})
        .cast<String, String>(),
  );

  @override
  bool operator ==(Object other) =>
      other is DayAssignment &&
      other.day == day &&
      const ListEquality<String>().equals(other.nurseIds, nurseIds) &&
      other.techId == techId &&
      other.tech16bId == tech16bId &&
      const ListEquality<String>().equals(other.shift16aIds, shift16aIds) &&
      const MapEquality<String, String>().equals(
        other.customShifts,
        customShifts,
      ) &&
      const MapEquality<String, String>().equals(
        other.extraShifts,
        extraShifts,
      );

  @override
  int get hashCode => Object.hash(
    day,
    const ListEquality<String>().hash(nurseIds),
    techId,
    tech16bId,
    const ListEquality<String>().hash(shift16aIds),
    const MapEquality<String, String>().hash(customShifts),
    const MapEquality<String, String>().hash(extraShifts),
  );

  @override
  String toString() =>
      'DayAssignment($day: $nurseIds${shift16aIds.isEmpty ? '' : ' (16A: $shift16aIds)'} + '
      '$techId${tech16bId == null ? '' : ' + $tech16bId(16B)'})';
}
