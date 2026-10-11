import 'package:collection/collection.dart';

import 'day_assignment.dart';

/// Bir ayın planı: istenmeyen günler ve oluşturulan nöbet listesi.
class MonthPlan {
  const MonthPlan({
    required this.year,
    required this.month,
    this.unavailableDays = const {},
    this.assignments = const {},
    this.generatedAt,
    this.isLocked = false,
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
      assignments.values.any((a) => a.includes(personId));

  MonthPlan copyWith({
    Map<String, List<int>>? unavailableDays,
    Map<int, DayAssignment>? assignments,
    DateTime? generatedAt,
    bool? isLocked,
  }) {
    return MonthPlan(
      year: year,
      month: month,
      unavailableDays: unavailableDays ?? this.unavailableDays,
      assignments: assignments ?? this.assignments,
      generatedAt: generatedAt ?? this.generatedAt,
      isLocked: isLocked ?? this.isLocked,
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
      other.isLocked == isLocked;

  @override
  int get hashCode => Object.hash(
    year,
    month,
    _unavailableEquality.hash(unavailableDays),
    _assignmentsEquality.hash(assignments),
    generatedAt,
    isLocked,
  );

  @override
  String toString() => 'MonthPlan($key, ${assignments.length} gün atanmış)';
}
