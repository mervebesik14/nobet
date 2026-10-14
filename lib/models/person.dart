import 'role.dart';

/// Nöbet listesindeki bir kişi.
class Person {
  const Person({
    required this.id,
    required this.name,
    required this.role,
    this.isActive = true,
    this.colorValue,
    this.isChargeNurse = false,
    this.inactiveFrom,
    this.inactiveUntil,
  });

  final String id;
  final String name;
  final Role role;

  /// Ayrılan kişi silinmez, pasifleştirilir; geçmiş listelerde adı kalır.
  final bool isActive;

  /// Listede ayırt etmek için renk (ARGB). Boşsa varsayılan renk kullanılır.
  final int? colorValue;

  /// Sorumlu hemşire: nöbet tutmadığı mesai günlerinde 7A (gündüz) çalışır;
  /// nöbet sayısı grup ortalamasına eşitlenmez, nöbete gerektiğinde yazılır.
  /// Yalnızca hemşireler için anlamlıdır.
  final bool isChargeNurse;

  /// Pasif döneminin ilk günü. Doluysa kişi [inactiveFrom]–[inactiveUntil]
  /// arasında (iki gün dahil) nöbete yazılmaz, dışında çalışır. Boş ve
  /// [isActive] false ise kişi tamamen pasiftir.
  final DateTime? inactiveFrom;

  /// Pasif döneminin son günü (dahil). Boşsa dönem süresizdir.
  final DateTime? inactiveUntil;

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Kişi [date] gününde çalışabilir mi (aktif mi)?
  bool isActiveOn(DateTime date) {
    final from = inactiveFrom;
    if (from == null) return isActive;
    final day = _day(date);
    if (day.isBefore(_day(from))) return true;
    final until = inactiveUntil;
    return until != null && day.isAfter(_day(until));
  }

  /// Pasif dönemi [date] günü itibarıyla bitmiş mi (ya da hiç yok mu)?
  /// Bitmiş ya da henüz başlamamış dönem kişiyi aktif saymaya engel değildir.
  bool hasEndedInactivity(DateTime date) {
    final until = inactiveUntil;
    return inactiveFrom != null &&
        until != null &&
        _day(date).isAfter(_day(until));
  }

  /// Kişi [year]/[month] ayında en az bir gün aktif mi?
  bool worksInMonth(int year, int month) {
    if (inactiveFrom == null) return isActive;
    final last = DateTime(year, month + 1, 0).day;
    for (var d = 1; d <= last; d++) {
      if (isActiveOn(DateTime(year, month, d))) return true;
    }
    return false;
  }

  /// [year]/[month] ayında, ayın bir kısmında çalıştığı halde pasif olduğu
  /// günler. Ayda hiç aktif değilse ya da tamamen aktifse boş.
  List<int> inactiveDaysIn(int year, int month) {
    if (inactiveFrom == null || !worksInMonth(year, month)) return const [];
    final last = DateTime(year, month + 1, 0).day;
    return [
      for (var d = 1; d <= last; d++)
        if (!isActiveOn(DateTime(year, month, d))) d,
    ];
  }

  Person copyWith({
    String? name,
    Role? role,
    bool? isActive,
    int? colorValue,
    bool clearColor = false,
    bool? isChargeNurse,
    DateTime? inactiveFrom,
    DateTime? inactiveUntil,
    bool clearInactiveFrom = false,
    bool clearInactiveUntil = false,
  }) {
    return Person(
      id: id,
      name: name ?? this.name,
      role: role ?? this.role,
      isActive: isActive ?? this.isActive,
      colorValue: clearColor ? null : (colorValue ?? this.colorValue),
      isChargeNurse: isChargeNurse ?? this.isChargeNurse,
      inactiveFrom: clearInactiveFrom
          ? null
          : (inactiveFrom ?? this.inactiveFrom),
      inactiveUntil: clearInactiveUntil || clearInactiveFrom
          ? null
          : (inactiveUntil ?? this.inactiveUntil),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'role': role.name,
    'isActive': isActive,
    'colorValue': colorValue,
    'isChargeNurse': isChargeNurse,
    'inactiveFrom': inactiveFrom?.toIso8601String(),
    'inactiveUntil': inactiveUntil?.toIso8601String(),
  };

  factory Person.fromJson(Map<String, dynamic> json) => Person(
    id: json['id'] as String,
    name: json['name'] as String,
    role: Role.fromName(json['role'] as String),
    isActive: json['isActive'] as bool? ?? true,
    colorValue: json['colorValue'] as int?,
    isChargeNurse: json['isChargeNurse'] as bool? ?? false,
    inactiveFrom: json['inactiveFrom'] == null
        ? null
        : DateTime.parse(json['inactiveFrom'] as String),
    inactiveUntil: json['inactiveUntil'] == null
        ? null
        : DateTime.parse(json['inactiveUntil'] as String),
  );

  @override
  bool operator ==(Object other) =>
      other is Person &&
      other.id == id &&
      other.name == name &&
      other.role == role &&
      other.isActive == isActive &&
      other.colorValue == colorValue &&
      other.isChargeNurse == isChargeNurse &&
      other.inactiveFrom == inactiveFrom &&
      other.inactiveUntil == inactiveUntil;

  @override
  int get hashCode => Object.hash(
    id,
    name,
    role,
    isActive,
    colorValue,
    isChargeNurse,
    inactiveFrom,
    inactiveUntil,
  );

  @override
  String toString() => 'Person($name, ${role.label})';
}
