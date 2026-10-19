import 'day_assignment.dart';

/// Nöbet listesinde yapılan bir değişikliğin kaydı: ne zaman, ne değişti ve
/// geri almak için değişiklikten önceki hâl.
class RosterEdit {
  const RosterEdit({
    required this.at,
    required this.title,
    this.lines = const [],
    this.before = const {},
    this.beforeOverrides = const {},
    this.beforeGeneratedAt,
    this.beforeSeed,
  });

  final DateTime at;

  /// Kısa başlık, ör. "Elle değişiklik", "Liste yeniden oluşturuldu".
  final String title;

  /// Ayrıntı satırları, ör. "3 Ekim: Ayşe yerine Hale".
  final List<String> lines;

  /// Değişiklikten önceki atamalar (geri alınca bu hâle dönülür).
  final Map<int, DayAssignment> before;

  /// Değişiklikten önceki elle 7A seçimleri.
  final Map<int, String> beforeOverrides;

  final DateTime? beforeGeneratedAt;
  final int? beforeSeed;

  Map<String, dynamic> toJson() => {
    'at': at.toIso8601String(),
    'title': title,
    'lines': lines,
    'before': [for (final a in before.values) a.toJson()],
    'beforeOverrides': {
      for (final e in beforeOverrides.entries) '${e.key}': e.value,
    },
    'beforeGeneratedAt': beforeGeneratedAt?.toIso8601String(),
    'beforeSeed': beforeSeed,
  };

  factory RosterEdit.fromJson(Map<String, dynamic> json) => RosterEdit(
    at: DateTime.parse(json['at'] as String),
    title: json['title'] as String,
    lines: (json['lines'] as List? ?? const []).cast<String>(),
    before: {
      for (final a in (json['before'] as List? ?? const []))
        (a as Map)['day'] as int: DayAssignment.fromJson(
          a.cast<String, dynamic>(),
        ),
    },
    beforeOverrides: {
      for (final e in (json['beforeOverrides'] as Map? ?? const {}).entries)
        int.parse(e.key as String): e.value as String,
    },
    beforeGeneratedAt: switch (json['beforeGeneratedAt']) {
      final String s => DateTime.parse(s),
      _ => null,
    },
    beforeSeed: json['beforeSeed'] as int?,
  );
}
