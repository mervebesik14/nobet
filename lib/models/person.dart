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

  /// Pasifliğin başladığı gün. Doluysa kişi bu günden önce çalışır, bu
  /// günden itibaren nöbete yazılmaz. Boş ve [isActive] false ise kişi
  /// tamamen pasiftir.
  final DateTime? inactiveFrom;

  /// Kişi [date] gününde çalışabilir mi (aktif mi)?
  bool isActiveOn(DateTime date) {
    final from = inactiveFrom;
    if (from == null) return isActive;
    return DateTime(
      date.year,
      date.month,
      date.day,
    ).isBefore(DateTime(from.year, from.month, from.day));
  }

  /// Kişi [year]/[month] ayında en az bir gün aktif mi?
  bool worksInMonth(int year, int month) => isActiveOn(DateTime(year, month));

  /// [year]/[month] ayında pasif olduğu günler (ay içinde pasife geçtiyse
  /// pasiflik gününden ay sonuna kadar). Ayda hiç aktif değilse ya da
  /// tamamen aktifse boş.
  List<int> inactiveDaysIn(int year, int month) {
    final from = inactiveFrom;
    if (from == null || !worksInMonth(year, month)) return const [];
    if (from.year != year || from.month != month) return const [];
    final last = DateTime(year, month + 1, 0).day;
    return [for (var d = from.day; d <= last; d++) d];
  }

  Person copyWith({
    String? name,
    Role? role,
    bool? isActive,
    int? colorValue,
    bool clearColor = false,
    bool? isChargeNurse,
    DateTime? inactiveFrom,
    bool clearInactiveFrom = false,
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
      other.inactiveFrom == inactiveFrom;

  @override
  int get hashCode => Object.hash(
    id,
    name,
    role,
    isActive,
    colorValue,
    isChargeNurse,
    inactiveFrom,
  );

  @override
  String toString() => 'Person($name, ${role.label})';
}
