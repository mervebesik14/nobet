import '../models/models.dart';
import 'day_shift_planner.dart';

/// Bir kişinin yıllık izin bakiyesi.
typedef LeaveBalance = ({int allowance, int used, int remaining});

/// Yıllık izin bakiyesi (saf Dart): yıl içindeki ayların yıllık izin
/// günlerinden iş günü olanlar (hafta sonu ve tam gün tatil sayılmaz)
/// kullanılmış sayılır.
class LeaveBalances {
  const LeaveBalances._();

  /// [year] yılında [personId]'nin kullandığı yıllık izin iş günü sayısı.
  static int used({
    required int year,
    required Iterable<MonthPlan> plans,
    required String personId,
    required Iterable<Holiday> holidays,
    required RosterSettings settings,
  }) {
    var n = 0;
    for (final plan in plans) {
      if (plan.year != year) continue;
      for (final d in plan.leaveOf(personId, LeaveType.annual).toSet()) {
        if (DayShiftPlanner.workdayHours(
              year: year,
              month: plan.month,
              day: d,
              holidays: holidays,
              settings: settings,
            ) !=
            null) {
          n++;
        }
      }
    }
    return n;
  }

  /// İzin hakkı girilmiş kişilerin bakiyeleri.
  static Map<String, LeaveBalance> forYear({
    required int year,
    required Iterable<MonthPlan> plans,
    required Iterable<Person> people,
    required Iterable<Holiday> holidays,
    required RosterSettings settings,
  }) => {
    for (final p in people)
      if (p.annualLeaveDays case final allowance?)
        p.id: () {
          final u = used(
            year: year,
            plans: plans,
            personId: p.id,
            holidays: holidays,
            settings: settings,
          );
          return (allowance: allowance, used: u, remaining: allowance - u);
        }(),
  };

  /// "8 / 20 gün kullanıldı · 12 kaldı" ya da aşıldıysa "… · 2 gün aşıldı".
  static String label(LeaveBalance b) =>
      '${b.used} / ${b.allowance} gün kullanıldı · '
      '${b.remaining >= 0 ? '${b.remaining} kaldı' : '${-b.remaining} gün aşıldı'}';
}
