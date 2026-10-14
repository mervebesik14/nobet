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

  Person copyWith({
    String? name,
    Role? role,
    bool? isActive,
    int? colorValue,
    bool clearColor = false,
    bool? isChargeNurse,
  }) {
    return Person(
      id: id,
      name: name ?? this.name,
      role: role ?? this.role,
      isActive: isActive ?? this.isActive,
      colorValue: clearColor ? null : (colorValue ?? this.colorValue),
      isChargeNurse: isChargeNurse ?? this.isChargeNurse,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'role': role.name,
    'isActive': isActive,
    'colorValue': colorValue,
    'isChargeNurse': isChargeNurse,
  };

  factory Person.fromJson(Map<String, dynamic> json) => Person(
    id: json['id'] as String,
    name: json['name'] as String,
    role: Role.fromName(json['role'] as String),
    isActive: json['isActive'] as bool? ?? true,
    colorValue: json['colorValue'] as int?,
    isChargeNurse: json['isChargeNurse'] as bool? ?? false,
  );

  @override
  bool operator ==(Object other) =>
      other is Person &&
      other.id == id &&
      other.name == name &&
      other.role == role &&
      other.isActive == isActive &&
      other.colorValue == colorValue &&
      other.isChargeNurse == isChargeNurse;

  @override
  int get hashCode =>
      Object.hash(id, name, role, isActive, colorValue, isChargeNurse);

  @override
  String toString() => 'Person($name, ${role.label})';
}
