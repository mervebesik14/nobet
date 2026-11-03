import 'person_totals.dart';

/// Kişi karnesindeki (yıllık, ay ay) sütunlar (saf Dart). Ay her zaman
/// vardır.
enum TotalsColumn {
  shifts('Nöbet'),
  weekend('Hafta sonu'),
  nationalHoliday('Resmi tatil'),
  religiousHoliday('Dini bayram'),
  everyOtherDay('Gün aşırı çift'),
  longGaps('4–5 gün ara'),
  dayShifts('7A gün'),
  attendedDays('Geldiği gün'),
  worked('Çalışılan saat'),
  required('Gereken saat'),
  overtime('Fazla saat');

  const TotalsColumn(this.label);

  final String label;

  num valueOf(PersonTotals t) => switch (this) {
    shifts => t.shifts,
    weekend => t.weekendShifts,
    nationalHoliday => t.nationalHolidayShifts,
    religiousHoliday => t.religiousHolidayShifts,
    everyOtherDay => t.everyOtherDayPairs,
    longGaps => t.longGaps,
    dayShifts => t.dayShifts,
    attendedDays => t.attendedDays,
    worked => t.workedHours,
    required => t.requiredHours,
    overtime => t.overtimeHours,
  };

  /// [selected] içinden, tanım sırasıyla.
  static List<TotalsColumn> ordered(Set<TotalsColumn> selected) => [
    for (final c in values)
      if (selected.contains(c)) c,
  ];

  /// Kaydedilmiş adlardan; tanınmayanlar atlanır.
  static Set<TotalsColumn> fromNames(Iterable<String> names) => {
    for (final n in names)
      for (final c in values)
        if (c.name == n) c,
  };
}
