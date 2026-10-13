import '../models/holiday.dart';

/// Yıllık izinle ilgili nöbet kuralları (saf Dart).
///
/// Kural: Yıllık izin bittikten sonra kişi ancak **ilk iş gününde** yeniden
/// nöbete girebilir. İzin bitişi ile ilk iş günü arasında kalan hafta sonu ve
/// resmi tatil günlerine de nöbet yazılmaz. Örneğin yıllık iznin son günü Cuma
/// ise Cumartesi–Pazar nöbet yazılmaz, ilk nöbet Pazartesiye yazılabilir.
///
/// Şua izni için bu kural uygulanmaz: şua izni bitince ertesi gün nöbet
/// yazılabilir.
class LeaveRules {
  const LeaveRules._();

  /// [year]/[month] için, bir kişinin [annualLeaveDays] (ayın günleri) yıllık
  /// izin günlerine bakarak, **her izin aralığının bitişinden sonraki ilk iş
  /// gününe kadar** kalan (iş günü olmayan) günleri döndürür. Bu günlerde de
  /// o kişiye nöbet yazılmaz. İzin günlerinin kendisi bu kümeye dahil değildir
  /// (onlar zaten ayrıca engellenir).
  ///
  /// İş günü = hafta içi (Pazartesi–Cuma) ve tam gün resmi tatil olmayan gün.
  /// Arife (yarım gün tatil) iş günü sayılır.
  static Set<int> postAnnualLeaveBlockedDays({
    required int year,
    required int month,
    required Iterable<int> annualLeaveDays,
    required Iterable<Holiday> holidays,
  }) {
    final leave = annualLeaveDays.toSet();
    if (leave.isEmpty) return const {};

    final daysInMonth = DateTime(year, month + 1, 0).day;
    final fullHolidays = <int>{
      for (final h in holidays)
        if (h.date.year == year && h.date.month == month && !h.isHalfDay)
          h.date.day,
    };

    bool isWorkday(int day) {
      final weekday = DateTime(year, month, day).weekday;
      if (weekday == DateTime.saturday || weekday == DateTime.sunday) {
        return false;
      }
      return !fullHolidays.contains(day);
    }

    final blocked = <int>{};
    for (final end in leave) {
      // Yalnızca aralık bitişlerinden ilerle (bir sonraki gün de izinliyse
      // burası bitiş değildir).
      if (leave.contains(end + 1)) continue;
      var day = end + 1;
      while (day <= daysInMonth && !isWorkday(day)) {
        blocked.add(day);
        day++;
      }
    }
    return blocked;
  }
}
