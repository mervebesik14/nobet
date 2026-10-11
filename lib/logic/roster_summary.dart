import '../models/day_assignment.dart';
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
  });

  final String personId;
  final String name;
  final Role role;
  final int shifts;
  final int weekendShifts;
  final int everyOtherDayPairs;
  final int workedHours;
  final double requiredHours;

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
    for (final a in assignments.values) {
      for (final id in a.nurseIds) {
        (worked[id] ??= {}).add(a.day);
        assignedRole[id] = Role.nurse;
      }
      if (a.techId case final id?) {
        (worked[id] ??= {}).add(a.day);
        assignedRole[id] = Role.radiologyTech;
      }
    }

    final byId = {for (final p in people) p.id: p};
    final rows = <PersonSummary>[];
    final included = {
      for (final p in people)
        if (p.isActive || worked.containsKey(p.id)) p.id,
      ...worked.keys,
    };
    for (final id in included) {
      final person = byId[id];
      final days = worked[id] ?? const <int>{};
      rows.add(
        PersonSummary(
          personId: id,
          name: person?.name ?? 'Silinmiş kişi',
          role: person?.role ?? assignedRole[id]!,
          shifts: days.length,
          weekendShifts: days.where(weekend.contains).length,
          everyOtherDayPairs: RosterGenerator.everyOtherDayPairs(days),
          workedHours: calc.workedHours(days.length),
          requiredHours: required,
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
      final group = rows.where((r) => r.role == role).toList();
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
