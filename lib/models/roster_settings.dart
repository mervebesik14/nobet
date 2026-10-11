/// Nöbet dağıtım kuralları ve mesai hesabı ayarları.
class RosterSettings {
  const RosterSettings({
    this.nursesPerDay = 2,
    this.techsPerDay = 1,
    this.shiftHours = 24,
    this.dailyRequiredHours = 7,
    this.maxEveryOtherDayChain = 2,
    this.maxExtraOverAverage,
    this.forbidConsecutiveDays = true,
    this.holidayCountsAsWeekend = true,
    this.halfDayHolidayIsHalfWorkday = true,
    this.halfDayRequiredHours = 5,
  });

  /// Her gün nöbet tutacak hemşire sayısı.
  final int nursesPerDay;

  /// Her gün nöbet tutacak radyoloji teknikeri sayısı.
  final int techsPerDay;

  /// Bir nöbetin süresi (saat).
  final int shiftHours;

  /// Resmi tatil olmayan bir hafta içi günün gerektirdiği çalışma saati.
  final double dailyRequiredHours;

  /// Gün aşırı zincirindeki en fazla nöbet sayısı. 2 ise 3-5 olur, 3-5-7 olmaz.
  final int maxEveryOtherDayChain;

  /// Kişi, rol grubunun ortalamasından en fazla bu kadar fazla nöbet tutabilir.
  /// Boşsa kural kapalıdır.
  final int? maxExtraOverAverage;

  /// Aynı kişiye art arda iki gün nöbet verilmez.
  final bool forbidConsecutiveDays;

  /// Resmi tatiller hafta sonu nöbeti olarak sayılır.
  final bool holidayCountsAsWeekend;

  /// Yarım gün tatil (arife) gereken saate [halfDayRequiredHours] olarak
  /// eklenir. Kapalıysa arife tam iş günü sayılır.
  final bool halfDayHolidayIsHalfWorkday;

  /// Hafta içine denk gelen arife gününün gerektirdiği çalışma saati.
  final double halfDayRequiredHours;

  RosterSettings copyWith({
    int? nursesPerDay,
    int? techsPerDay,
    int? shiftHours,
    double? dailyRequiredHours,
    int? maxEveryOtherDayChain,
    int? maxExtraOverAverage,
    bool clearMaxExtraOverAverage = false,
    bool? forbidConsecutiveDays,
    bool? holidayCountsAsWeekend,
    bool? halfDayHolidayIsHalfWorkday,
    double? halfDayRequiredHours,
  }) {
    return RosterSettings(
      nursesPerDay: nursesPerDay ?? this.nursesPerDay,
      techsPerDay: techsPerDay ?? this.techsPerDay,
      shiftHours: shiftHours ?? this.shiftHours,
      dailyRequiredHours: dailyRequiredHours ?? this.dailyRequiredHours,
      maxEveryOtherDayChain:
          maxEveryOtherDayChain ?? this.maxEveryOtherDayChain,
      maxExtraOverAverage: clearMaxExtraOverAverage
          ? null
          : (maxExtraOverAverage ?? this.maxExtraOverAverage),
      forbidConsecutiveDays:
          forbidConsecutiveDays ?? this.forbidConsecutiveDays,
      holidayCountsAsWeekend:
          holidayCountsAsWeekend ?? this.holidayCountsAsWeekend,
      halfDayHolidayIsHalfWorkday:
          halfDayHolidayIsHalfWorkday ?? this.halfDayHolidayIsHalfWorkday,
      halfDayRequiredHours: halfDayRequiredHours ?? this.halfDayRequiredHours,
    );
  }

  Map<String, dynamic> toJson() => {
    'nursesPerDay': nursesPerDay,
    'techsPerDay': techsPerDay,
    'shiftHours': shiftHours,
    'dailyRequiredHours': dailyRequiredHours,
    'maxEveryOtherDayChain': maxEveryOtherDayChain,
    'maxExtraOverAverage': maxExtraOverAverage,
    'forbidConsecutiveDays': forbidConsecutiveDays,
    'holidayCountsAsWeekend': holidayCountsAsWeekend,
    'halfDayHolidayIsHalfWorkday': halfDayHolidayIsHalfWorkday,
    'halfDayRequiredHours': halfDayRequiredHours,
  };

  /// Eksik alanlar varsayılan değerini alır (eski yedeklerle uyum için).
  factory RosterSettings.fromJson(Map<String, dynamic> json) {
    const d = RosterSettings();
    return RosterSettings(
      nursesPerDay: json['nursesPerDay'] as int? ?? d.nursesPerDay,
      techsPerDay: json['techsPerDay'] as int? ?? d.techsPerDay,
      shiftHours: json['shiftHours'] as int? ?? d.shiftHours,
      dailyRequiredHours:
          (json['dailyRequiredHours'] as num?)?.toDouble() ??
          d.dailyRequiredHours,
      maxEveryOtherDayChain:
          json['maxEveryOtherDayChain'] as int? ?? d.maxEveryOtherDayChain,
      maxExtraOverAverage: json['maxExtraOverAverage'] as int?,
      forbidConsecutiveDays:
          json['forbidConsecutiveDays'] as bool? ?? d.forbidConsecutiveDays,
      holidayCountsAsWeekend:
          json['holidayCountsAsWeekend'] as bool? ?? d.holidayCountsAsWeekend,
      halfDayHolidayIsHalfWorkday:
          json['halfDayHolidayIsHalfWorkday'] as bool? ??
          d.halfDayHolidayIsHalfWorkday,
      halfDayRequiredHours:
          (json['halfDayRequiredHours'] as num?)?.toDouble() ??
          d.halfDayRequiredHours,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is RosterSettings &&
      other.nursesPerDay == nursesPerDay &&
      other.techsPerDay == techsPerDay &&
      other.shiftHours == shiftHours &&
      other.dailyRequiredHours == dailyRequiredHours &&
      other.maxEveryOtherDayChain == maxEveryOtherDayChain &&
      other.maxExtraOverAverage == maxExtraOverAverage &&
      other.forbidConsecutiveDays == forbidConsecutiveDays &&
      other.holidayCountsAsWeekend == holidayCountsAsWeekend &&
      other.halfDayHolidayIsHalfWorkday == halfDayHolidayIsHalfWorkday &&
      other.halfDayRequiredHours == halfDayRequiredHours;

  @override
  int get hashCode => Object.hash(
    nursesPerDay,
    techsPerDay,
    shiftHours,
    dailyRequiredHours,
    maxEveryOtherDayChain,
    maxExtraOverAverage,
    forbidConsecutiveDays,
    holidayCountsAsWeekend,
    halfDayHolidayIsHalfWorkday,
    halfDayRequiredHours,
  );
}
