import 'turkish_collation.dart';
import 'turkish_dates.dart';

/// Her ay kendiliğinden istenmeyen güne işlenen istek (saf Dart): ör.
/// "Ayşe her Çarşamba olmaz", "Banu Eylül'e kadar hafta sonu olmaz",
/// "Nur her ayın 1'i olmaz". [until] doluysa o günden sonra işlenmez.
class RecurringRequest {
  const RecurringRequest({
    required this.id,
    required this.personId,
    this.weekdays = const {},
    this.monthDays = const {},
    this.until,
  });

  final String id;
  final String personId;

  /// 1 = Pazartesi … 7 = Pazar.
  final Set<int> weekdays;

  /// Ayın günleri (ör. 1, 15); ayda olmayan gün atlanır.
  final Set<int> monthDays;

  /// Son geçerli gün (dahil); boşsa süresiz.
  final DateTime? until;

  static const weekdayNames = [
    'Pazartesi',
    'Salı',
    'Çarşamba',
    'Perşembe',
    'Cuma',
    'Cumartesi',
    'Pazar',
  ];

  bool get isEmpty => weekdays.isEmpty && monthDays.isEmpty;

  /// [year]/[month] ayında istenmeyen günler.
  Set<int> daysIn(int year, int month) {
    final last = DateTime(year, month + 1, 0).day;
    final end = until;
    return {
      for (var d = 1; d <= last; d++)
        if ((weekdays.contains(DateTime(year, month, d).weekday) ||
                monthDays.contains(d)) &&
            (end == null ||
                !DateTime(
                  year,
                  month,
                  d,
                ).isAfter(DateTime(end.year, end.month, end.day))))
          d,
    };
  }

  /// "her Çarşamba, ayın 1'i · 30 Haziran 2027'ye kadar"
  String describe() {
    final parts = <String>[
      if (weekdays.length == 2 && weekdays.containsAll({6, 7}))
        'hafta sonları'
      else if (weekdays.isNotEmpty)
        'her ${[for (final w in weekdays.toList()..sort()) weekdayNames[w - 1]].join(', ')}',
      if (monthDays.isNotEmpty)
        'ayın ${(monthDays.toList()..sort()).join(', ')}. günü',
    ];
    final end = until;
    return '${parts.join(', ')}'
        '${end == null ? '' : ' · ${end.day} ${turkishMonthNames[end.month - 1]} ${end.year} sonuna kadar'}';
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'personId': personId,
    if (weekdays.isNotEmpty) 'weekdays': weekdays.toList()..sort(),
    if (monthDays.isNotEmpty) 'monthDays': monthDays.toList()..sort(),
    if (until != null) 'until': until!.toIso8601String(),
  };

  factory RecurringRequest.fromJson(Map<String, dynamic> json) =>
      RecurringRequest(
        id: json['id'] as String,
        personId: json['personId'] as String,
        weekdays: {
          for (final w in json['weekdays'] as List? ?? const []) w as int,
        },
        monthDays: {
          for (final d in json['monthDays'] as List? ?? const []) d as int,
        },
        until: json['until'] == null
            ? null
            : DateTime.parse(json['until'] as String),
      );

  /// Kişi → bu ayın istenmeyen günleri (boş olanlar atlanır).
  static Map<String, Set<int>> forMonth(
    Iterable<RecurringRequest> requests,
    int year,
    int month,
  ) {
    final out = <String, Set<int>>{};
    for (final r in requests) {
      final days = r.daysIn(year, month);
      if (days.isNotEmpty) (out[r.personId] ??= {}).addAll(days);
    }
    return out;
  }

  /// Önizleme satırları: "Ayşe: 3, 10, 17 (her Çarşamba)".
  static List<String> preview(
    Iterable<RecurringRequest> requests,
    int year,
    int month,
    String Function(String) name,
  ) {
    final lines = <String>[];
    for (final r in requests) {
      final days = r.daysIn(year, month).toList()..sort();
      if (days.isEmpty) continue;
      lines.add('${name(r.personId)}: ${days.join(', ')} (${r.describe()})');
    }
    return lines..sort(compareTurkish);
  }
}
