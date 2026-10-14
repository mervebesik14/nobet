import '../models/holiday.dart';

/// Yıllık izinle ilgili nöbet kuralları (saf Dart).
///
/// **İzinden önce:** Kişinin izinden önceki son nöbeti, izinden önceki son
/// iş gününden bir önceki gündür. İzinden önceki son iş günü ve onunla izin
/// arasında kalan hafta sonu / resmi tatil günlerine nöbet yazılmaz. Örneğin
/// izin Pazartesi başlıyorsa Cuma–Cumartesi–Pazar nöbet yazılmaz; son nöbet
/// Perşembe olur.
///
/// **İzinden sonra:** Kişi izin bittikten sonra ancak ilk iş gününde yeniden
/// nöbete girebilir. İzin bitişi ile ilk iş günü arasında kalan hafta sonu ve
/// resmi tatil günlerine nöbet yazılmaz. Örneğin izin Cuma bitiyorsa
/// Cumartesi–Pazar nöbet yazılmaz; ilk nöbet Pazartesi olur.
///
/// Şua izni için bu kurallar uygulanmaz.
///
/// İş günü = hafta içi (Pazartesi–Cuma) ve tam gün resmi tatil olmayan gün.
/// Arife (yarım gün tatil) iş günü sayılır. Kurallar yalnızca planın ayı
/// içinde uygulanır.
class LeaveRules {
  const LeaveRules._();

  /// İzin öncesi ve sonrası kurallarının birlikte kapattığı günler.
  /// İzin günlerinin kendisi bu kümeye dahil değildir.
  static Set<int> annualLeaveBlockedDays({
    required int year,
    required int month,
    required Iterable<int> annualLeaveDays,
    required Iterable<Holiday> holidays,
  }) => {
    ...preAnnualLeaveBlockedDays(
      year: year,
      month: month,
      annualLeaveDays: annualLeaveDays,
      holidays: holidays,
    ),
    ...postAnnualLeaveBlockedDays(
      year: year,
      month: month,
      annualLeaveDays: annualLeaveDays,
      holidays: holidays,
    ),
  };

  /// Her izin aralığının başlangıcından geriye doğru, izinden önceki son iş
  /// gününe kadar (o gün dahil) kalan günler.
  static Set<int> preAnnualLeaveBlockedDays({
    required int year,
    required int month,
    required Iterable<int> annualLeaveDays,
    required Iterable<Holiday> holidays,
  }) {
    final leave = annualLeaveDays.toSet();
    if (leave.isEmpty) return const {};
    final isWorkday = _workdayTest(year, month, holidays);

    final blocked = <int>{};
    for (final start in leave) {
      // Yalnızca aralık başlangıçlarından geriye git.
      if (leave.contains(start - 1)) continue;
      var day = start - 1;
      while (day >= 1) {
        blocked.add(day);
        if (isWorkday(day)) break;
        day--;
      }
    }
    return blocked.difference(leave);
  }

  /// Her izin aralığının bitişinden sonraki ilk iş gününe kadar kalan (iş günü
  /// olmayan) günler.
  static Set<int> postAnnualLeaveBlockedDays({
    required int year,
    required int month,
    required Iterable<int> annualLeaveDays,
    required Iterable<Holiday> holidays,
  }) {
    final leave = annualLeaveDays.toSet();
    if (leave.isEmpty) return const {};
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final isWorkday = _workdayTest(year, month, holidays);

    final blocked = <int>{};
    for (final end in leave) {
      // Yalnızca aralık bitişlerinden ileri git.
      if (leave.contains(end + 1)) continue;
      var day = end + 1;
      while (day <= daysInMonth && !isWorkday(day)) {
        blocked.add(day);
        day++;
      }
    }
    return blocked.difference(leave);
  }

  static bool Function(int day) _workdayTest(
    int year,
    int month,
    Iterable<Holiday> holidays,
  ) {
    final fullHolidays = <int>{
      for (final h in holidays)
        if (h.date.year == year && h.date.month == month && !h.isHalfDay)
          h.date.day,
    };
    return (day) {
      final weekday = DateTime(year, month, day).weekday;
      if (weekday == DateTime.saturday || weekday == DateTime.sunday) {
        return false;
      }
      return !fullHolidays.contains(day);
    };
  }
}
