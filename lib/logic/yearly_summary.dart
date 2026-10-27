import '../models/holiday.dart';
import '../models/month_plan.dart';
import '../models/person.dart';
import '../models/role.dart';
import '../models/roster_settings.dart';
import 'day_shift_planner.dart';
import 'person_totals.dart';
import 'roster_summary.dart';
import 'turkish_collation.dart';

/// Yıllık özetin bir satırı.
class YearlyRow {
  const YearlyRow({
    required this.personId,
    required this.name,
    required this.role,
    required this.totals,
    this.byMonth = const {},
    this.isChargeNurse = false,
  });

  final String personId;
  final String name;
  final Role role;
  final PersonTotals totals;

  /// Ay (1..12) → o ayın toplamları; yalnız listesi olan aylar.
  final Map<int, PersonTotals> byMonth;

  /// Sorumlu hemşire rol ortalamalarına girmez.
  final bool isChargeNurse;
}

/// Kayıtlı ay listelerini kişi başı toplar: yıllık özet ekranı ve
/// algoritmanın yıl içi dengesi için.
class YearlySummary {
  const YearlySummary({required this.rows, required this.months});

  /// Rol sırasıyla, her rolde Türkçe ada göre.
  final List<YearlyRow> rows;

  /// Toplama giren (listesi oluşturulmuş) aylar, sıralı.
  final List<int> months;

  Map<String, PersonTotals> get byId => {
    for (final r in rows) r.personId: r.totals,
  };

  /// Kişinin [plan] ayında çalışabildiği gün sayısı: ayın günleri eksi
  /// izin / rapor günleri, pasif ve işe başlamadan önceki günler.
  static int _availableDays(MonthPlan plan, Person? person, String id) {
    final off = {
      ...plan.leaveDaysOf(id),
      ...?person?.inactiveDaysIn(plan.year, plan.month),
    };
    return plan.daysInMonth - off.length;
  }

  /// [row] kişisinin [month] ayındaki değerinin, aynı roldeki kişilerin o
  /// ayki ortalamasından farkı (sorumlu hemşire ortalamaya girmez). Kişinin
  /// o ay kaydı yoksa null.
  double? deviation(YearlyRow row, int month, num Function(PersonTotals) pick) {
    final own = row.byMonth[month];
    if (own == null) return null;
    final group = [
      for (final r in rows)
        if (r.role == row.role && !r.isChargeNurse)
          if (r.byMonth[month] case final t?) pick(t),
    ];
    if (group.isEmpty) return 0;
    final mean = group.fold<num>(0, (a, b) => a + b) / group.length;
    return pick(own) - mean;
  }

  /// [year] yılının listesi oluşturulmuş aylarını toplar. [beforeMonth]
  /// verilirse yalnızca ondan önceki aylar (yeni ay oluşturulurken yıl içi
  /// toplam için).
  factory YearlySummary.build({
    required int year,
    required Iterable<MonthPlan> plans,
    required Iterable<Person> people,
    required Iterable<Holiday> holidays,
    required RosterSettings settings,
    int? beforeMonth,
  }) {
    final selected =
        plans
            .where(
              (p) =>
                  p.year == year &&
                  p.hasRoster &&
                  (beforeMonth == null || p.month < beforeMonth),
            )
            .toList()
          ..sort((a, b) => a.month.compareTo(b.month));

    final byKey = {for (final p in plans) p.key: p};
    final byPerson = {for (final p in people) p.id: p};
    final totals = <String, PersonTotals>{};
    final monthly = <String, Map<int, PersonTotals>>{};
    final info = <String, (String, Role)>{};
    final charge = <String>{};
    for (final plan in selected) {
      final monthHolidays = holidays.where(
        (h) => h.date.year == plan.year && h.date.month == plan.month,
      );
      final prev = DateTime(plan.year, plan.month - 1);
      final previous = byKey[MonthPlan.keyFor(prev.year, prev.month)];
      final dayShifts = DayShiftPlanner.plan(
        year: plan.year,
        month: plan.month,
        assignments: plan.assignments,
        people: people,
        holidays: monthHolidays,
        settings: settings,
        leaveDays: plan.leaveDays,
        unavailableDays: plan.unavailableDays,
        previousMonthLastDay: {
          ...?previous?.assignments[previous.daysInMonth]?.personIds,
        },
        overrides: plan.dayShiftOverrides,
      );
      final allDayShifts = [
        ...dayShifts.values,
        ...DayShiftPlanner.manual(
          year: plan.year,
          month: plan.month,
          days: plan.techDayShifts,
          assignments: plan.assignments,
          holidays: monthHolidays,
          settings: settings,
        ),
      ];
      final summary = RosterSummary.build(
        year: plan.year,
        month: plan.month,
        assignments: plan.assignments,
        people: people,
        holidays: holidays.where(
          (h) => h.date.year == plan.year && h.date.month == plan.month,
        ),
        settings: settings,
        leaveDays: plan.leaveDays,
        dayShifts: allDayShifts,
        // Yalnız hemşire listesinde teknikerler o ay sayılmaz.
        onlyRoles: plan.nurseOnly ? const {Role.nurse} : null,
      );
      for (final r in summary.people) {
        info[r.personId] = (r.name, r.role);
        if (r.isChargeNurse) charge.add(r.personId);
        final month = PersonTotals(
          shifts: r.shifts,
          weekendShifts: r.weekendShifts,
          nationalHolidayShifts: r.nationalHolidayShifts,
          religiousHolidayShifts: r.religiousHolidayShifts,
          everyOtherDayPairs: r.everyOtherDayPairs,
          longGaps: r.longGaps,
          workedHours: r.workedHours,
          requiredHours: r.requiredHours,
          overtimeHours: r.overtimeHours,
          months: 1,
          availableDays: _availableDays(plan, byPerson[r.personId], r.personId),
        );
        (monthly[r.personId] ??= {})[plan.month] = month;
        totals[r.personId] =
            (totals[r.personId] ?? const PersonTotals()) + month;
      }
    }

    final rows =
        [
          for (final e in totals.entries)
            YearlyRow(
              personId: e.key,
              name: info[e.key]!.$1,
              role: info[e.key]!.$2,
              totals: e.value,
              byMonth: monthly[e.key] ?? const {},
              isChargeNurse: charge.contains(e.key),
            ),
        ]..sort((a, b) {
          final r = a.role.index.compareTo(b.role.index);
          return r != 0 ? r : compareTurkish(a.name, b.name);
        });
    return YearlySummary(
      rows: rows,
      months: [for (final p in selected) p.month],
    );
  }
}
