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
/// Kurallar tarih üzerinden çalışır, ay sınırını aşar: 2 Kasım Pazartesi
/// başlayan izin Ekim'in son günlerini, 30 Ekim Cuma biten izin Kasım'ın ilk
/// günlerini kapatabilir. İzinden sonra kuralı şua izni için de uygulanır
/// ([blockedDaysInMonth] şua tarihleriyle, `before: false`).
///
/// **Şua izninden önce:** İzin başlangıcından önceki [radiationGapDays] (2)
/// takvim gününde nöbet tutulmaz (hafta sonu / tatil fark etmez). Örneğin
/// şua izni 10'unda başlıyorsa 8 ve 9'unda nöbet yazılmaz.
///
/// İş günü = hafta içi (Pazartesi–Cuma) ve tam gün resmi tatil olmayan gün.
/// Arife (yarım gün tatil) iş günü sayılır.
class LeaveRules {
  const LeaveRules._();

  /// [annualLeave] yıllık izin tarihlerine (her aydan olabilir) göre,
  /// [year]/[month] ayında izin öncesi ve sonrası kurallarının kapattığı
  /// günler. İzin günlerinin kendisi dahil değildir.
  static Set<int> blockedDaysInMonth({
    required int year,
    required int month,
    required Iterable<DateTime> annualLeave,
    required Iterable<Holiday> holidays,
    bool before = true,
    bool after = true,
  }) {
    final leave = {for (final d in annualLeave) _day(d)};
    if (leave.isEmpty) return const {};
    final fullHolidays = {
      for (final h in holidays)
        if (!h.isHalfDay) _day(h.date),
    };
    bool isWorkday(DateTime d) =>
        d.weekday != DateTime.saturday &&
        d.weekday != DateTime.sunday &&
        !fullHolidays.contains(d);

    final blocked = <DateTime>{};
    for (final day in leave) {
      // İzin aralığının başlangıcından geriye: son iş günü dahil.
      if (before && !leave.contains(_shift(day, -1))) {
        var d = _shift(day, -1);
        for (var i = 0; i < _maxGap; i++) {
          blocked.add(d);
          if (isWorkday(d)) break;
          d = _shift(d, -1);
        }
      }
      // İzin aralığının bitişinden ileriye: ilk iş günü hariç.
      if (after && !leave.contains(_shift(day, 1))) {
        var d = _shift(day, 1);
        for (var i = 0; i < _maxGap && !isWorkday(d); i++) {
          blocked.add(d);
          d = _shift(d, 1);
        }
      }
    }
    return {
      for (final d in blocked.difference(leave))
        if (d.year == year && d.month == month) d.day,
    };
  }

  /// Yalnız [year]/[month] ayının izin günleri ([annualLeaveDays], ayın
  /// günleri) için izin öncesi ve sonrası kurallarının kapattığı günler.
  static Set<int> annualLeaveBlockedDays({
    required int year,
    required int month,
    required Iterable<int> annualLeaveDays,
    required Iterable<Holiday> holidays,
  }) => blockedDaysInMonth(
    year: year,
    month: month,
    annualLeave: [for (final d in annualLeaveDays) DateTime(year, month, d)],
    holidays: holidays,
  );

  /// Yalnız izin öncesi kuralı (ayın günleriyle).
  static Set<int> preAnnualLeaveBlockedDays({
    required int year,
    required int month,
    required Iterable<int> annualLeaveDays,
    required Iterable<Holiday> holidays,
  }) => blockedDaysInMonth(
    year: year,
    month: month,
    annualLeave: [for (final d in annualLeaveDays) DateTime(year, month, d)],
    holidays: holidays,
    after: false,
  );

  /// Yalnız izin sonrası kuralı (ayın günleriyle).
  static Set<int> postAnnualLeaveBlockedDays({
    required int year,
    required int month,
    required Iterable<int> annualLeaveDays,
    required Iterable<Holiday> holidays,
  }) => blockedDaysInMonth(
    year: year,
    month: month,
    annualLeave: [for (final d in annualLeaveDays) DateTime(year, month, d)],
    holidays: holidays,
    before: false,
  );

  /// Şua izninden önce nöbet tutulmayan gün sayısı.
  static const radiationGapDays = 2;

  /// [radiationLeave] şua izni tarihlerine (her aydan olabilir) göre,
  /// [year]/[month] ayında izin başlangıcından önceki [radiationGapDays]
  /// günden bu aya düşenler. İzin günlerinin kendisi dahil değildir.
  static Set<int> radiationBlockedDaysInMonth({
    required int year,
    required int month,
    required Iterable<DateTime> radiationLeave,
  }) {
    final leave = {for (final d in radiationLeave) _day(d)};
    final blocked = <DateTime>{
      for (final day in leave)
        if (!leave.contains(_shift(day, -1)))
          for (var i = 1; i <= radiationGapDays; i++) _shift(day, -i),
    };
    return {
      for (final d in blocked.difference(leave))
        if (d.year == year && d.month == month) d.day,
    };
  }

  /// Bayram + hafta sonu gibi uzun ardışık tatillerde bile yeter.
  static const _maxGap = 14;

  /// Saat dilimi / yaz saati kaymasından etkilenmeyen gün anahtarı.
  static DateTime _day(DateTime d) => DateTime.utc(d.year, d.month, d.day);

  static DateTime _shift(DateTime d, int days) =>
      DateTime.utc(d.year, d.month, d.day + days);
}
