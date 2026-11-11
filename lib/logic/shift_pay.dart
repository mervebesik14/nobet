import '../models/roster_settings.dart';

/// Tahmini nöbet ücreti dökümü.
typedef PayEstimate = ({
  double paidHours,
  double normalHours,
  double holidayHours,
  double gross,
  double stamp,
  double net,
  bool capped,
});

/// Nöbet (fazla mesai) ücreti tahmini (saf Dart). Ödenen saat, gereken
/// saati aşan çalışılan saattir; ayda en fazla [RosterSettings.payHourCap]
/// saat ödenir (0 = sınır yok). Resmi tatil / bayram nöbetlerinin saatleri ×1,25, riskli
/// birimde tüm saatler ×1,5 (bayram ×1,875). Yalnız damga vergisi kesilir.
/// Gerçek bordro kurumun hesabına göre değişebilir; bu bir tahmindir.
class ShiftPay {
  const ShiftPay._();

  /// 2026 damga vergisi oranı (binde 7,59).
  static const stampRate = 0.00759;

  static const holidayFactor = 1.25;
  static const riskyFactor = 1.5;

  static bool enabled(RosterSettings s) => s.shiftHourlyRate > 0;

  /// [overtimeHours] gereken saati aşan saat; [holidayShiftHours] tam gün
  /// resmi tatil ve bayram günlerindeki nöbet saatleri.
  static PayEstimate estimate({
    required double overtimeHours,
    required double holidayShiftHours,
    required RosterSettings settings,
  }) {
    final cap = settings.payHourCap.toDouble();
    final paid = overtimeHours < 0
        ? 0.0
        : (cap > 0 && overtimeHours > cap ? cap : overtimeHours);
    final holiday = holidayShiftHours > paid ? paid : holidayShiftHours;
    final normal = paid - holiday;
    final rate =
        settings.shiftHourlyRate * (settings.riskyUnit ? riskyFactor : 1);
    final gross = rate * (normal + holiday * holidayFactor);
    final stamp = gross * stampRate;
    return (
      paidHours: paid,
      normalHours: normal,
      holidayHours: holiday,
      gross: gross,
      stamp: stamp,
      net: gross - stamp,
      capped: cap > 0 && overtimeHours > cap,
    );
  }
}
