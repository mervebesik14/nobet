import 'roster_summary.dart';

/// Liste paylaşılırken altındaki kişi başı özette gösterilebilecek
/// sütunlar (saf Dart). Ad ve görev her zaman vardır.
enum SummaryColumn {
  shifts('Toplam nöbet'),
  weekend('Hafta sonu nöbet'),
  nationalHoliday('Resmi tatil nöbeti'),
  religiousHoliday('Dini bayram nöbeti'),
  everyOtherDay('Gün aşırı çift'),
  longGaps('4–5 gün ara'),
  dayShifts('7A gün'),
  worked('Çalışılan saat'),
  required('Gereken saat'),
  overtime('Fazla mesai');

  const SummaryColumn(this.label);

  final String label;

  /// Kişinin bu sütundaki değeri.
  num valueOf(PersonSummary p) => switch (this) {
    shifts => p.shifts,
    weekend => p.weekendShifts,
    nationalHoliday => p.nationalHolidayShifts,
    religiousHoliday => p.religiousHolidayShifts,
    everyOtherDay => p.everyOtherDayPairs,
    longGaps => p.longGaps,
    dayShifts => p.dayShifts,
    worked => p.workedHours,
    required => p.requiredHours,
    overtime => p.overtimeHours,
  };

  /// Rol ortalaması satırındaki değer; ortalaması olmayan sütunda null.
  num? averageOf(RoleAverage a, RosterSummary summary) => switch (this) {
    shifts => a.shifts,
    weekend => a.weekendShifts,
    nationalHoliday => a.nationalHolidayShifts,
    religiousHoliday => a.religiousHolidayShifts,
    everyOtherDay => a.everyOtherDayPairs,
    longGaps || dayShifts => null,
    worked => a.workedHours,
    required => summary.requiredHours,
    overtime => a.overtimeHours,
  };

  /// [selected] içinden, bu özette gösterilecekler (sıra sabit). Resmi
  /// tatil, dini bayram ve 7A sütunları kimsede yoksa düşer.
  static List<SummaryColumn> visible(
    RosterSummary summary,
    Set<SummaryColumn> selected,
  ) => [
    for (final c in values)
      if (selected.contains(c))
        if (switch (c) {
          nationalHoliday ||
          religiousHoliday ||
          dayShifts => summary.people.any((p) => c.valueOf(p) > 0),
          _ => true,
        })
          c,
  ];

  /// Kaydetmek için adlar ↔ sütunlar; tanınmayan adlar atlanır.
  static Set<SummaryColumn> fromNames(Iterable<String> names) => {
    for (final n in names)
      for (final c in values)
        if (c.name == n) c,
  };
}
