import 'package:collection/collection.dart';

/// Ayın bir gününün nöbetçileri.
class DayAssignment {
  const DayAssignment({
    required this.day,
    this.nurseIds = const [],
    this.techId,
  });

  /// Ayın günü (1..31).
  final int day;

  /// Nöbetçi hemşirelerin kimlikleri (normalde 2 kişi).
  final List<String> nurseIds;

  /// Nöbetçi radyoloji teknikerinin kimliği; henüz atanmadıysa boş.
  final String? techId;

  /// Bu günde nöbet tutan herkes.
  List<String> get personIds => [...nurseIds, ?techId];

  bool includes(String personId) => personIds.contains(personId);

  DayAssignment copyWith({
    List<String>? nurseIds,
    String? techId,
    bool clearTech = false,
  }) {
    return DayAssignment(
      day: day,
      nurseIds: nurseIds ?? this.nurseIds,
      techId: clearTech ? null : (techId ?? this.techId),
    );
  }

  Map<String, dynamic> toJson() => {
    'day': day,
    'nurseIds': nurseIds,
    'techId': techId,
  };

  factory DayAssignment.fromJson(Map<String, dynamic> json) => DayAssignment(
    day: json['day'] as int,
    nurseIds: (json['nurseIds'] as List? ?? const []).cast<String>(),
    techId: json['techId'] as String?,
  );

  @override
  bool operator ==(Object other) =>
      other is DayAssignment &&
      other.day == day &&
      const ListEquality<String>().equals(other.nurseIds, nurseIds) &&
      other.techId == techId;

  @override
  int get hashCode =>
      Object.hash(day, const ListEquality<String>().hash(nurseIds), techId);

  @override
  String toString() => 'DayAssignment($day: $nurseIds + $techId)';
}
