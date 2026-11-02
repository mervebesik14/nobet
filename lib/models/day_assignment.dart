import 'package:collection/collection.dart';

/// Ayın bir gününün nöbetçileri.
class DayAssignment {
  const DayAssignment({
    required this.day,
    this.nurseIds = const [],
    this.techId,
    this.tech16bId,
    this.shift16aIds = const [],
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

  /// Kişinin bu günkü vardiyası: "16B", "16A" ya da "24".
  String shiftCode(String personId) => isSecondaryTech(personId)
      ? '16B'
      : is16a(personId)
      ? '16A'
      : '24';

  DayAssignment copyWith({
    List<String>? nurseIds,
    String? techId,
    bool clearTech = false,
    String? tech16bId,
    bool clearTech16b = false,
    List<String>? shift16aIds,
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
    );
  }

  Map<String, dynamic> toJson() => {
    'day': day,
    'nurseIds': nurseIds,
    'techId': techId,
    'tech16bId': tech16bId,
    if (shift16aIds.isNotEmpty) 'nurse16aIds': shift16aIds,
  };

  factory DayAssignment.fromJson(Map<String, dynamic> json) => DayAssignment(
    day: json['day'] as int,
    nurseIds: (json['nurseIds'] as List? ?? const []).cast<String>(),
    techId: json['techId'] as String?,
    tech16bId: json['tech16bId'] as String?,
    shift16aIds: (json['nurse16aIds'] as List? ?? const []).cast<String>(),
  );

  @override
  bool operator ==(Object other) =>
      other is DayAssignment &&
      other.day == day &&
      const ListEquality<String>().equals(other.nurseIds, nurseIds) &&
      other.techId == techId &&
      other.tech16bId == tech16bId &&
      const ListEquality<String>().equals(other.shift16aIds, shift16aIds);

  @override
  int get hashCode => Object.hash(
    day,
    const ListEquality<String>().hash(nurseIds),
    techId,
    tech16bId,
    const ListEquality<String>().hash(shift16aIds),
  );

  @override
  String toString() =>
      'DayAssignment($day: $nurseIds${shift16aIds.isEmpty ? '' : ' (16A: $shift16aIds)'} + '
      '$techId${tech16bId == null ? '' : ' + $tech16bId(16B)'})';
}
