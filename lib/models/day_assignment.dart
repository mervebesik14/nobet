import 'package:collection/collection.dart';

/// Ayın bir gününün nöbetçileri.
class DayAssignment {
  const DayAssignment({
    required this.day,
    this.nurseIds = const [],
    this.techId,
    this.tech16bId,
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

  /// Bu günde nöbet tutan herkes.
  List<String> get personIds => [...nurseIds, ?techId, ?tech16bId];

  bool includes(String personId) => personIds.contains(personId);

  /// [personId] bu gün 16B vardiyasında mı? (Değilse 24 kabul edilir.)
  bool isSecondaryTech(String personId) => personId == tech16bId;

  DayAssignment copyWith({
    List<String>? nurseIds,
    String? techId,
    bool clearTech = false,
    String? tech16bId,
    bool clearTech16b = false,
  }) {
    return DayAssignment(
      day: day,
      nurseIds: nurseIds ?? this.nurseIds,
      techId: clearTech ? null : (techId ?? this.techId),
      tech16bId: clearTech16b ? null : (tech16bId ?? this.tech16bId),
    );
  }

  Map<String, dynamic> toJson() => {
    'day': day,
    'nurseIds': nurseIds,
    'techId': techId,
    'tech16bId': tech16bId,
  };

  factory DayAssignment.fromJson(Map<String, dynamic> json) => DayAssignment(
    day: json['day'] as int,
    nurseIds: (json['nurseIds'] as List? ?? const []).cast<String>(),
    techId: json['techId'] as String?,
    tech16bId: json['tech16bId'] as String?,
  );

  @override
  bool operator ==(Object other) =>
      other is DayAssignment &&
      other.day == day &&
      const ListEquality<String>().equals(other.nurseIds, nurseIds) &&
      other.techId == techId &&
      other.tech16bId == tech16bId;

  @override
  int get hashCode => Object.hash(
    day,
    const ListEquality<String>().hash(nurseIds),
    techId,
    tech16bId,
  );

  @override
  String toString() =>
      'DayAssignment($day: $nurseIds + $techId${tech16bId == null ? '' : ' + $tech16bId(16B)'})';
}
