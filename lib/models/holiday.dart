/// Resmi tatil ya da elle eklenen tatil günü.
class Holiday {
  Holiday({
    required DateTime date,
    required this.name,
    this.isHalfDay = false,
    this.isPredefined = false,
  }) : date = DateTime(date.year, date.month, date.day);

  /// Tatilin günü; saat bilgisi atılır (yerel gece yarısı).
  final DateTime date;
  final String name;

  /// Arife gibi yarım gün tatil.
  final bool isHalfDay;

  /// Uygulamayla gelen Türkiye tatili mi (true), kullanıcı mı ekledi (false).
  final bool isPredefined;

  /// Saklama anahtarı: `yyyy-MM-dd`.
  String get key => keyFor(date);

  static String keyFor(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  Holiday copyWith({
    DateTime? date,
    String? name,
    bool? isHalfDay,
    bool? isPredefined,
  }) {
    return Holiday(
      date: date ?? this.date,
      name: name ?? this.name,
      isHalfDay: isHalfDay ?? this.isHalfDay,
      isPredefined: isPredefined ?? this.isPredefined,
    );
  }

  Map<String, dynamic> toJson() => {
    'date': key,
    'name': name,
    'isHalfDay': isHalfDay,
    'isPredefined': isPredefined,
  };

  factory Holiday.fromJson(Map<String, dynamic> json) => Holiday(
    date: DateTime.parse(json['date'] as String),
    name: json['name'] as String,
    isHalfDay: json['isHalfDay'] as bool? ?? false,
    isPredefined: json['isPredefined'] as bool? ?? false,
  );

  @override
  bool operator ==(Object other) =>
      other is Holiday &&
      other.date == date &&
      other.name == name &&
      other.isHalfDay == isHalfDay &&
      other.isPredefined == isPredefined;

  @override
  int get hashCode => Object.hash(date, name, isHalfDay, isPredefined);

  @override
  String toString() => 'Holiday($key, $name${isHalfDay ? ', yarım gün' : ''})';
}
