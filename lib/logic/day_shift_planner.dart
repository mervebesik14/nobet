import '../models/day_assignment.dart';
import '../models/holiday.dart';
import '../models/person.dart';
import '../models/role.dart';
import '../models/roster_settings.dart';

/// Bir mesai gününün 7A (gündüz) çalışanı.
class DayShift {
  const DayShift({
    required this.day,
    required this.personId,
    required this.hours,
    required this.isSubstitute,
  });

  final int day;
  final String personId;

  /// O günün mesai saati: normal gün günlük saat (7), arife yarım gün saati.
  final double hours;

  /// Sorumlu hemşire yerine başka bir hemşire mi çalışıyor?
  final bool isSubstitute;

  @override
  bool operator ==(Object other) =>
      other is DayShift &&
      other.day == day &&
      other.personId == personId &&
      other.hours == hours &&
      other.isSubstitute == isSubstitute;

  @override
  int get hashCode => Object.hash(day, personId, hours, isSubstitute);

  @override
  String toString() =>
      'DayShift($day, $personId${isSubstitute ? ', yerine' : ''})';
}

/// 7A planı (saf Dart).
///
/// Sorumlu hemşire, ayın her mesai gününde (hafta içi, tam gün resmi tatil
/// olmayan gün; arife dahil) 7A çalışır. Şu günlerde çalışamaz ve 7A'ya
/// başka bir hemşire yazılır:
/// - o gün 24 saat nöbeti varsa,
/// - önceki gün 24 saat nöbeti varsa (nöbet ertesi dinlenir),
/// - o gün izinliyse (yıllık / şua).
///
/// Yerine yazılacak hemşire de o gün nöbetli, nöbet ertesi, izinli ya da
/// nöbet istemediği günde olmamalı. Adaylar arasında bu ay en az 7A yerine
/// geçmiş, eşitlikte en az nöbeti olan seçilir. [overrides] ile elle
/// seçilen kişi o günün 7A'sına yazılır. Sorumlu hemşire yoksa
/// 7A planı boştur.
class DayShiftPlanner {
  const DayShiftPlanner._();

  static Map<int, DayShift> plan({
    required int year,
    required int month,
    required Map<int, DayAssignment> assignments,
    required Iterable<Person> people,
    required Iterable<Holiday> holidays,
    required RosterSettings settings,
    Map<String, List<int>> leaveDays = const {},
    Map<String, List<int>> unavailableDays = const {},
    Set<String> previousMonthLastDay = const {},
    Map<int, String> overrides = const {},
  }) {
    final nurses = [
      for (final p in people)
        if (p.worksInMonth(year, month) && p.role == Role.nurse) p,
    ];
    Person? charge;
    for (final p in nurses) {
      if (p.isChargeNurse) {
        charge = p;
        break;
      }
    }
    if (charge == null) return const {};

    final daysInMonth = DateTime(year, month + 1, 0).day;
    double? hoursOn(int d) => workdayHours(
      year: year,
      month: month,
      day: d,
      holidays: holidays,
      settings: settings,
    );

    bool onDuty(String id, int d) {
      if (d == 0) return previousMonthLastDay.contains(id);
      return assignments[d]?.includes(id) ?? false;
    }

    // Ay içinde pasife geçenin pasif günleri izin gibi sayılır.
    final inactive = {
      for (final p in nurses) p.id: p.inactiveDaysIn(year, month).toSet(),
    };
    bool onLeave(String id, int d) =>
        (leaveDays[id]?.contains(d) ?? false) ||
        (inactive[id]?.contains(d) ?? false);

    bool canWork(String id, int d) =>
        !onDuty(id, d) && !onDuty(id, d - 1) && !onLeave(id, d);

    final shiftCount = {
      for (final p in nurses)
        p.id: assignments.values.where((a) => a.includes(p.id)).length,
    };
    final substituteCount = <String, int>{};
    final others = [
      for (final p in nurses)
        if (p.id != charge.id) p,
    ]..sort((a, b) => a.id.compareTo(b.id));

    final result = <int, DayShift>{};
    for (var d = 1; d <= daysInMonth; d++) {
      final hours = hoursOn(d);
      if (hours == null) continue;
      // Elle seçilen kişi otomatik seçimin önüne geçer.
      if (overrides[d] case final id?) {
        final substitute = id != charge.id;
        if (substitute) {
          substituteCount[id] = (substituteCount[id] ?? 0) + 1;
        }
        result[d] = DayShift(
          day: d,
          personId: id,
          hours: hours,
          isSubstitute: substitute,
        );
        continue;
      }
      if (canWork(charge.id, d)) {
        result[d] = DayShift(
          day: d,
          personId: charge.id,
          hours: hours,
          isSubstitute: false,
        );
        continue;
      }
      Person? best;
      for (final p in others) {
        if (!canWork(p.id, d)) continue;
        if (unavailableDays[p.id]?.contains(d) ?? false) continue;
        if (best == null) {
          best = p;
          continue;
        }
        final c = (substituteCount[p.id] ?? 0).compareTo(
          substituteCount[best.id] ?? 0,
        );
        if (c < 0 || (c == 0 && shiftCount[p.id]! < shiftCount[best.id]!)) {
          best = p;
        }
      }
      if (best == null) continue;
      substituteCount[best.id] = (substituteCount[best.id] ?? 0) + 1;
      result[d] = DayShift(
        day: d,
        personId: best.id,
        hours: hours,
        isSubstitute: true,
      );
    }
    return result;
  }

  /// [day] gününün mesai saati (7A süresi): hafta içi günlük saat, arife
  /// ayara göre yarım gün; hafta sonu ya da tam gün tatilse null.
  static double? workdayHours({
    required int year,
    required int month,
    required int day,
    required Iterable<Holiday> holidays,
    required RosterSettings settings,
  }) {
    final weekday = DateTime(year, month, day).weekday;
    if (weekday == DateTime.saturday || weekday == DateTime.sunday) {
      return null;
    }
    Holiday? h;
    for (final x in holidays) {
      if (x.date.year == year && x.date.month == month && x.date.day == day) {
        h = x;
        break;
      }
    }
    if (h == null) return settings.dailyRequiredHours;
    if (!h.isHalfDay) return null;
    return settings.halfDayHolidayIsHalfWorkday
        ? settings.halfDayRequiredHours
        : settings.dailyRequiredHours;
  }

  /// Elle yazılan 7A'lar ([MonthPlan.techDayShifts]): kişi → günler. Mesai
  /// günü olmayan ya da o gün 24 / 16B nöbetinde olunan günler atlanır.
  static List<DayShift> manual({
    required int year,
    required int month,
    required Map<String, List<int>> days,
    required Map<int, DayAssignment> assignments,
    required Iterable<Holiday> holidays,
    required RosterSettings settings,
  }) => [
    for (final MapEntry(key: id, value: list) in days.entries)
      for (final d in list)
        if (!(assignments[d]?.includes(id) ?? false))
          if (workdayHours(
                year: year,
                month: month,
                day: d,
                holidays: holidays,
                settings: settings,
              )
              case final hours?)
            DayShift(day: d, personId: id, hours: hours, isSubstitute: false),
  ]..sort((a, b) => a.day.compareTo(b.day));
}
