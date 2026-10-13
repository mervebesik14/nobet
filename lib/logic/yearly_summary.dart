import '../models/holiday.dart';
import '../models/month_plan.dart';
import '../models/person.dart';
import '../models/role.dart';
import '../models/roster_settings.dart';
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
  });

  final String personId;
  final String name;
  final Role role;
  final PersonTotals totals;
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

    final totals = <String, PersonTotals>{};
    final info = <String, (String, Role)>{};
    for (final plan in selected) {
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
      );
      for (final r in summary.people) {
        info[r.personId] = (r.name, r.role);
        totals[r.personId] =
            (totals[r.personId] ?? const PersonTotals()) +
            PersonTotals(
              shifts: r.shifts,
              weekendShifts: r.weekendShifts,
              everyOtherDayPairs: r.everyOtherDayPairs,
              workedHours: r.workedHours,
              requiredHours: r.requiredHours,
              overtimeHours: r.overtimeHours,
              months: 1,
            );
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
