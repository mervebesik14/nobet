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

/// Bir kişinin yıl içindeki izinleri (saf Dart): türüne göre ay ay günler
/// ve sayılar. Yıllık izin iş günü (hafta sonu ve tam gün tatil sayılmaz),
/// şua izni ve rapor takvim günü olarak sayılır.
class YearLeaves {
  const YearLeaves({required this.days, required this.counts});

  /// Tür → ay → günler (sıralı).
  final Map<LeaveType, Map<int, List<int>>> days;

  /// Tür → sayı ([countOf] kuralıyla).
  final Map<LeaveType, int> counts;

  int count(LeaveType type) => counts[type] ?? 0;

  bool get isEmpty => counts.values.every((c) => c == 0);

  /// Sayım birimi: "iş günü" ya da "gün".
  static String unitOf(LeaveType type) =>
      type == LeaveType.annual ? 'iş günü' : 'gün';

  /// Bir ayın [days] günlerinden sayılanlar: yıllık izinde iş günleri,
  /// diğerlerinde hepsi.
  static int countOf(
    LeaveType type, {
    required int year,
    required int month,
    required Iterable<int> days,
    required Iterable<Holiday> holidays,
    required RosterSettings settings,
  }) {
    final unique = days.toSet();
    if (type != LeaveType.annual) return unique.length;
    return unique
        .where(
          (d) =>
              DayShiftPlanner.workdayHours(
                year: year,
                month: month,
                day: d,
                holidays: holidays,
                settings: settings,
              ) !=
              null,
        )
        .length;
  }

  /// [year] yılındaki tüm ay planlarından (listesi olmayan aylar dahil)
  /// kişi başına izinler.
  static Map<String, YearLeaves> forYear({
    required int year,
    required Iterable<MonthPlan> plans,
    required Iterable<Person> people,
    required Iterable<Holiday> holidays,
    required RosterSettings settings,
  }) {
    final sorted = plans.where((p) => p.year == year).toList()
      ..sort((a, b) => a.month.compareTo(b.month));
    return {
      for (final person in people)
        person.id: () {
          final days = <LeaveType, Map<int, List<int>>>{};
          final counts = <LeaveType, int>{};
          for (final plan in sorted) {
            for (final type in LeaveType.values) {
              final list = plan.leaveOf(person.id, type).toSet().toList()
                ..sort();
              if (list.isEmpty) continue;
              (days[type] ??= {})[plan.month] = list;
              counts[type] =
                  (counts[type] ?? 0) +
                  countOf(
                    type,
                    year: year,
                    month: plan.month,
                    days: list,
                    holidays: holidays,
                    settings: settings,
                  );
            }
          }
          return YearLeaves(days: days, counts: counts);
        }(),
    };
  }
}
