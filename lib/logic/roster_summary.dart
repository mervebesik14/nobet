import '../models/day_assignment.dart';
import 'day_shift_planner.dart';
import '../models/holiday.dart';
import '../models/person.dart';
import '../models/role.dart';
import '../models/roster_settings.dart';
import 'roster_generator.dart';
import 'turkish_collation.dart';
import 'work_hours_calculator.dart';

/// Bir kişinin aylık nöbet özeti.
class PersonSummary {
  const PersonSummary({
    required this.personId,
    required this.name,
    required this.role,
    required this.shifts,
    required this.weekendShifts,
    required this.everyOtherDayPairs,
    required this.workedHours,
    required this.requiredHours,
    this.secondaryShifts = 0,
    this.dayShifts = 0,
    this.isChargeNurse = false,
  });

  final String personId;
  final String name;
  final Role role;
  final int shifts;
  final int weekendShifts;
  final int everyOtherDayPairs;

  /// 24/16B nöbet saatleri + 7A saatleri.
  final double workedHours;
  final double requiredHours;

  /// 7A (gündüz mesaisi) gün sayısı.
  final int dayShifts;

  /// Sorumlu hemşire: rol ortalamasına girmez.
  final bool isChargeNurse;

  /// Bunların kaçı 16B (hafif) vardiyası; teknikerler için anlamlıdır.
  final int secondaryShifts;

  /// 24 saat vardiyası sayısı.
  int get primaryShifts => shifts - secondaryShifts;

  /// max(0, çalışılan − gereken)
  double get overtimeHours =>
      workedHours > requiredHours ? workedHours - requiredHours : 0;

  /// max(0, gereken − çalışılan)
  double get missingHours =>
      requiredHours > workedHours ? requiredHours - workedHours : 0;
}

/// Bir rol grubunun ortalamaları.
class RoleAverage {
  const RoleAverage({
    required this.role,
    required this.people,
    required this.shifts,
    required this.weekendShifts,
    required this.everyOtherDayPairs,
    required this.workedHours,
    required this.overtimeHours,
  });

  final Role role;

  /// Ortalamaya giren kişi sayısı.
  final int people;
  final double shifts;
  final double weekendShifts;
  final double everyOtherDayPairs;
  final double workedHours;
  final double overtimeHours;
}

/// Liste sonundaki özet tablo: kişi başı toplam nöbet, hafta sonu nöbeti,
/// gün aşırı çift sayısı, çalışılan / gereken saat, fazla mesai ve rol
/// grubu ortalamaları.
class RosterSummary {
  const RosterSummary({
    required this.people,
    required this.averages,
    required this.requiredHours,
  });

  /// Rol sırasıyla (önce hemşireler), her rolde Türkçe ada göre.
  final List<PersonSummary> people;

  /// Yalnızca özette kişisi olan roller.
  final Map<Role, RoleAverage> averages;

  /// Ayın herkes için aynı olan gereken saati.
  final double requiredHours;

  /// Özeti hesaplar. [people] içinde pasifler de olabilir: aktif kişiler
  /// nöbeti olmasa da, pasifler yalnızca bu ay nöbeti varsa listelenir.
  /// [people] içinde olmayan (silinmiş) kişilerin nöbetleri "Silinmiş kişi"
  /// adıyla ve atandığı rolle gösterilir.
  factory RosterSummary.build({
    required int year,
    required int month,
    required Map<int, DayAssignment> assignments,
    required Iterable<Person> people,
    required Iterable<Holiday> holidays,
    required RosterSettings settings,
    Set<Role>? onlyRoles,
    Map<String, List<int>> leaveDays = const {},
    Map<int, DayShift> dayShifts = const {},
  }) {
    final calc = WorkHoursCalculator(settings);
    final required = calc.requiredHours(year, month, holidays);
    final weekend = RosterGenerator.weekendDays(
      year,
      month,
      holidays,
      settings,
    );

    final worked = <String, Set<int>>{};
    final assignedRole = <String, Role>{};
    // 16B (hafif) vardiyadaki tekniker günleri; çalışılan saat farklı.
    final secondary = <String, Set<int>>{};
    for (final a in assignments.values) {
      for (final id in a.nurseIds) {
        (worked[id] ??= {}).add(a.day);
        assignedRole[id] = Role.nurse;
      }
      if (a.techId case final id?) {
        (worked[id] ??= {}).add(a.day);
        assignedRole[id] = Role.radiologyTech;
      }
      if (a.tech16bId case final id?) {
        (worked[id] ??= {}).add(a.day);
        assignedRole[id] = Role.radiologyTech;
        (secondary[id] ??= {}).add(a.day);
      }
    }

    // Kişi → 7A gün sayısı ve saati.
    final dayCount = <String, int>{};
    final dayHours = <String, double>{};
    for (final s in dayShifts.values) {
      dayCount[s.personId] = (dayCount[s.personId] ?? 0) + 1;
      dayHours[s.personId] = (dayHours[s.personId] ?? 0) + s.hours;
    }

    final byId = {for (final p in people) p.id: p};
    final rows = <PersonSummary>[];
    bool roleAllowed(Role? role) =>
        onlyRoles == null || onlyRoles.contains(role);
    final included = {
      for (final p in people)
        if ((p.worksInMonth(year, month) || worked.containsKey(p.id)) &&
            roleAllowed(p.role))
          p.id,
      for (final id in worked.keys)
        if (roleAllowed(byId[id]?.role ?? assignedRole[id])) id,
    };
    for (final id in included) {
      final person = byId[id];
      final days = worked[id] ?? const <int>{};
      final light = secondary[id] ?? const <int>{};
      final full = days.length - light.length;
      // İzin günleri (yıllık + şua) kişinin gereken saatinden düşülür
      // (altına inmez).
      final leave = leaveDays[id] ?? const <int>[];
      final personRequired = leave.isEmpty
          ? required
          : (required - calc.leaveDeduction(year, month, holidays, leave))
                .clamp(0.0, required);
      rows.add(
        PersonSummary(
          personId: id,
          name: person?.name ?? 'Silinmiş kişi',
          role: person?.role ?? assignedRole[id]!,
          shifts: days.length,
          secondaryShifts: light.length,
          weekendShifts: days.where(weekend.contains).length,
          everyOtherDayPairs: RosterGenerator.everyOtherDayPairs(days),
          // 24 vardiyaları tam saat, 16B vardiyaları kısa saat sayılır.
          // 7A günleri o günün mesai saati kadar eklenir.
          workedHours:
              calc.workedHours(full) +
              light.length * settings.secondaryTechShiftHours +
              (dayHours[id] ?? 0),
          requiredHours: personRequired,
          dayShifts: dayCount[id] ?? 0,
          isChargeNurse: person?.isChargeNurse ?? false,
        ),
      );
    }
    rows.sort((a, b) {
      final r = a.role.index.compareTo(b.role.index);
      return r != 0 ? r : compareTurkish(a.name, b.name);
    });

    double mean(Iterable<num> values) =>
        values.fold<double>(0, (s, v) => s + v) / values.length;

    final averages = <Role, RoleAverage>{};
    for (final role in Role.values) {
      // Sorumlu hemşire nöbet dengesine girmediği için ortalamaya da girmez.
      final group = rows
          .where((r) => r.role == role && !r.isChargeNurse)
          .toList();
      if (group.isEmpty) continue;
      averages[role] = RoleAverage(
        role: role,
        people: group.length,
        shifts: mean(group.map((r) => r.shifts)),
        weekendShifts: mean(group.map((r) => r.weekendShifts)),
        everyOtherDayPairs: mean(group.map((r) => r.everyOtherDayPairs)),
        workedHours: mean(group.map((r) => r.workedHours)),
        overtimeHours: mean(group.map((r) => r.overtimeHours)),
      );
    }

    return RosterSummary(
      people: rows,
      averages: averages,
      requiredHours: required,
    );
  }
}
