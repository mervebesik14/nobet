/// Kullanıcının tanımladığı özel mesai (ör. "19A": 13:00'te başlar, 19
/// saat). [fillsSeat] açıksa o günün nöbet koltuğunu doldurur ve kurallarda
/// nöbet sayılır (16A gibi); kapalıysa ek mesaidir (7A gibi, koltuk
/// doldurmaz). Herkese yazılabilir.
class CustomShift {
  const CustomShift({
    required this.code,
    this.startMinute = 8 * 60,
    required this.hours,
    this.fillsSeat = true,
  });

  /// Listede görünen kısa ad (ör. "19A"); tekildir.
  final String code;

  /// Başlangıç, gece yarısından dakika (ör. 13:00 → 780).
  final int startMinute;

  /// Süre (saat); çalışılan saate eklenir.
  final double hours;

  /// O günün nöbet koltuğunu doldurur mu?
  final bool fillsSeat;

  int get startHour => startMinute ~/ 60;

  /// Bitiş, gece yarısından dakika (0–1439; ertesi güne geçebilir).
  int get endMinute => (startMinute + (hours * 60).round()) % (24 * 60);

  static String clock(int minute) =>
      '${(minute ~/ 60).toString().padLeft(2, '0')}:'
      '${(minute % 60).toString().padLeft(2, '0')}';

  String get startLabel => clock(startMinute);

  String get endLabel => clock(endMinute);

  /// "13:00–08:00 · 19 sa · nöbet koltuğu"
  String get description {
    final h = hours == hours.roundToDouble()
        ? hours.toInt().toString()
        : hours.toString().replaceAll('.', ',');
    return '$startLabel–$endLabel · $h sa · '
        '${fillsSeat ? 'nöbet koltuğu' : 'ek mesai'}';
  }

  /// Ad karşılaştırması: boşluk atılır, büyük harf.
  static String normalize(String code) =>
      code.replaceAll(RegExp(r'\s+'), '').toUpperCase();

  /// Ayrılmış adlar: hazır vardiyalar ve izin kısaltmaları.
  static const reserved = {'24', '16', '16A', '16B', '7A', 'R', 'Y.İ.', 'Ş.İ.'};

  CustomShift copyWith({int? startMinute, double? hours, bool? fillsSeat}) =>
      CustomShift(
        code: code,
        startMinute: startMinute ?? this.startMinute,
        hours: hours ?? this.hours,
        fillsSeat: fillsSeat ?? this.fillsSeat,
      );

  Map<String, dynamic> toJson() => {
    'code': code,
    'startMinute': startMinute,
    'hours': hours,
    'fillsSeat': fillsSeat,
  };

  factory CustomShift.fromJson(Map<String, dynamic> json) => CustomShift(
    code: json['code'] as String,
    startMinute: json['startMinute'] as int? ?? 8 * 60,
    hours: (json['hours'] as num).toDouble(),
    fillsSeat: json['fillsSeat'] as bool? ?? true,
  );

  @override
  bool operator ==(Object other) =>
      other is CustomShift &&
      other.code == code &&
      other.startMinute == startMinute &&
      other.hours == hours &&
      other.fillsSeat == fillsSeat;

  @override
  int get hashCode => Object.hash(code, startMinute, hours, fillsSeat);

  @override
  String toString() => 'CustomShift($code, $description)';
}
