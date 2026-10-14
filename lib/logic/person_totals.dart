/// Bir kişinin birden çok ay boyunca biriken nöbet toplamları.
class PersonTotals {
  const PersonTotals({
    this.shifts = 0,
    this.weekendShifts = 0,
    this.everyOtherDayPairs = 0,
    this.workedHours = 0,
    this.requiredHours = 0,
    this.overtimeHours = 0,
    this.months = 0,
  });

  final int shifts;
  final int weekendShifts;
  final int everyOtherDayPairs;
  final double workedHours;
  final double requiredHours;

  /// Ay ay hesaplanan fazla mesailerin toplamı (her ay max(0, ...)).
  final double overtimeHours;

  /// Toplama giren ay sayısı.
  final int months;

  PersonTotals operator +(PersonTotals o) => PersonTotals(
    shifts: shifts + o.shifts,
    weekendShifts: weekendShifts + o.weekendShifts,
    everyOtherDayPairs: everyOtherDayPairs + o.everyOtherDayPairs,
    workedHours: workedHours + o.workedHours,
    requiredHours: requiredHours + o.requiredHours,
    overtimeHours: overtimeHours + o.overtimeHours,
    months: months + o.months,
  );
}
