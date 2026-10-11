import 'dart:math';

import '../models/holiday.dart';
import '../models/roster_settings.dart';

/// Bir ayın gereken çalışma saatinin dökümü.
class RequiredHours {
  const RequiredHours({
    required this.fullWorkdays,
    required this.halfWorkdays,
    required this.hours,
  });

  /// Tatil olmayan hafta içi günler.
  final int fullWorkdays;

  /// Hafta içine denk gelen yarım gün tatiller (arifeler). Ayar kapalıysa
  /// bunlar [fullWorkdays] içinde sayılır ve burası 0 olur.
  final int halfWorkdays;

  final double hours;

  @override
  String toString() =>
      'RequiredHours($fullWorkdays tam + $halfWorkdays yarım = $hours saat)';
}

/// Mesai hesabı: gereken saat, çalışılan saat, fazla mesai.
///
/// Gereken saat = ayın resmi tatil olmayan hafta içi günleri × günlük saat;
/// hafta içine denk gelen arife (yarım gün tatil) ayardaki arife saati
/// (varsayılan 5) kadar sayılır.
/// Çalışılan saat = nöbet sayısı × nöbet süresi.
class WorkHoursCalculator {
  const WorkHoursCalculator(this.settings);

  final RosterSettings settings;

  /// [year]/[month] için gereken saatin dökümü. [holidays] içinde başka
  /// aylara ait tatiller olabilir, yok sayılır. Hafta sonuna denk gelen
  /// tatiller gereken saati değiştirmez.
  RequiredHours requiredHoursBreakdown(
    int year,
    int month,
    Iterable<Holiday> holidays,
  ) {
    final byDay = <int, Holiday>{
      for (final h in holidays)
        if (h.date.year == year && h.date.month == month) h.date.day: h,
    };
    final daysInMonth = DateTime(year, month + 1, 0).day;

    var full = 0;
    var half = 0;
    for (var day = 1; day <= daysInMonth; day++) {
      final weekday = DateTime(year, month, day).weekday;
      if (weekday == DateTime.saturday || weekday == DateTime.sunday) continue;
      final holiday = byDay[day];
      if (holiday == null) {
        full++;
      } else if (holiday.isHalfDay) {
        if (settings.halfDayHolidayIsHalfWorkday) {
          half++;
        } else {
          full++;
        }
      }
    }

    return RequiredHours(
      fullWorkdays: full,
      halfWorkdays: half,
      hours:
          full * settings.dailyRequiredHours +
          half * settings.halfDayRequiredHours,
    );
  }

  /// [year]/[month] için gereken çalışma saati.
  double requiredHours(int year, int month, Iterable<Holiday> holidays) =>
      requiredHoursBreakdown(year, month, holidays).hours;

  /// [shiftCount] nöbetin karşılığı çalışılan saat.
  int workedHours(int shiftCount) => shiftCount * settings.shiftHours;

  /// Fazla mesai = max(0, çalışılan − gereken).
  double overtimeHours(int shiftCount, double requiredHours) =>
      max(0, workedHours(shiftCount) - requiredHours);

  /// Eksik çalışma = max(0, gereken − çalışılan).
  double missingHours(int shiftCount, double requiredHours) =>
      max(0, requiredHours - workedHours(shiftCount));
}
