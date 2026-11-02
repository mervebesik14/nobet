import 'package:collection/collection.dart';

/// Ayın bir gününün nöbetçileri.
class DayAssignment {
  const DayAssignment({
    required this.day,
    this.nurseIds = const [],
    this.techId,
    this.tech16bId,
    this.nurse16aIds = const [],
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

  /// [nurseIds] içinden 16A (16:00–08:00) vardiyasındaki hemşireler; elle
  /// yazılır. Koltuğu doldurur, kurallarda nöbet sayılır, 16 saat.
  final List<String> nurse16aIds;

  /// Hemşire 16A vardiyasının saati.
  static const nurse16aHours = 16;

  /// Bu günde nöbet tutan herkes.
  List<String> get personIds => [...nurseIds, ?techId, ?tech16bId];

  bool includes(String personId) => personIds.contains(personId);

  /// [personId] bu gün 16B vardiyasında mı? (Değilse 24 kabul edilir.)
  bool isSecondaryTech(String personId) => personId == tech16bId;

  /// [personId] bu gün 16A vardiyasındaki hemşire mi?
  bool isNurse16a(String personId) =>
      nurse16aIds.contains(personId) && nurseIds.contains(personId);

  /// Kişinin bu günkü vardiyası: "16B", "16A" ya da "24".
  String shiftCode(String personId) => isSecondaryTech(personId)
      ? '16B'
      : isNurse16a(personId)
      ? '16A'
      : '24';

  DayAssignment copyWith({
    List<String>? nurseIds,
    String? techId,
    bool clearTech = false,
    String? tech16bId,
    bool clearTech16b = false,
    List<String>? nurse16aIds,
  }) {
    final nurses = nurseIds ?? this.nurseIds;
    return DayAssignment(
      day: day,
      nurseIds: nurses,
      techId: clearTech ? null : (techId ?? this.techId),
      tech16bId: clearTech16b ? null : (tech16bId ?? this.tech16bId),
      // Günden çıkan hemşirenin 16A işareti düşer.
      nurse16aIds: [
        for (final id in nurse16aIds ?? this.nurse16aIds)
          if (nurses.contains(id)) id,
      ],
    );
  }

  Map<String, dynamic> toJson() => {
    'day': day,
    'nurseIds': nurseIds,
    'techId': techId,
    'tech16bId': tech16bId,
    if (nurse16aIds.isNotEmpty) 'nurse16aIds': nurse16aIds,
  };

  factory DayAssignment.fromJson(Map<String, dynamic> json) => DayAssignment(
    day: json['day'] as int,
    nurseIds: (json['nurseIds'] as List? ?? const []).cast<String>(),
    techId: json['techId'] as String?,
    tech16bId: json['tech16bId'] as String?,
    nurse16aIds: (json['nurse16aIds'] as List? ?? const []).cast<String>(),
  );

  @override
  bool operator ==(Object other) =>
      other is DayAssignment &&
      other.day == day &&
      const ListEquality<String>().equals(other.nurseIds, nurseIds) &&
      other.techId == techId &&
      other.tech16bId == tech16bId &&
      const ListEquality<String>().equals(other.nurse16aIds, nurse16aIds);

  @override
  int get hashCode => Object.hash(
    day,
    const ListEquality<String>().hash(nurseIds),
    techId,
    tech16bId,
    const ListEquality<String>().hash(nurse16aIds),
  );

  @override
  String toString() =>
      'DayAssignment($day: $nurseIds${nurse16aIds.isEmpty ? '' : ' (16A: $nurse16aIds)'} + '
      '$techId${tech16bId == null ? '' : ' + $tech16bId(16B)'})';
}
