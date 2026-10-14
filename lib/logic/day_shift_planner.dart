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
/// geçmiş, eşitlikte en az nöbeti olan seçilir. Sorumlu hemşire yoksa
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
    final byDay = <int, Holiday>{
      for (final h in holidays)
        if (h.date.year == year && h.date.month == month) h.date.day: h,
    };

    /// Mesai saati; mesai günü değilse null.
    double? hoursOn(int d) {
      final weekday = DateTime(year, month, d).weekday;
      if (weekday == DateTime.saturday || weekday == DateTime.sunday) {
        return null;
      }
      final h = byDay[d];
      if (h == null) return settings.dailyRequiredHours;
      if (!h.isHalfDay) return null;
      return settings.halfDayHolidayIsHalfWorkday
          ? settings.halfDayRequiredHours
          : settings.dailyRequiredHours;
    }

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
}
