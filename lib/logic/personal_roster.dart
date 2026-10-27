import '../models/month_plan.dart';
import '../models/person.dart';
import 'day_shift_planner.dart';
import 'turkish_dates.dart';

/// Kişinin bir nöbet günü: kendi vardiyası ve o günün tüm nöbetçileri.
class PersonalShift {
  const PersonalShift({
    required this.day,
    required this.shift,
    required this.nurses,
    required this.techs,
    this.isWeekend = false,
  });

  final int day;

  /// Kişinin kendi vardiyası: "24" ya da "16B".
  final String shift;

  /// O gün nöbetçi hemşireler (kişi dahil).
  final List<String> nurses;

  /// O gün nöbetçi radyoloji teknikerleri; iki tekniker varsa "(24)" /
  /// "(16B)" ekli.
  final List<String> techs;

  /// Hafta sonu ya da (ayara göre) resmi tatil günü mü?
  final bool isWeekend;
}

/// Bir kişinin aylık programı: nöbetler, 7A günleri ve izinler.
class PersonalRosterData {
  const PersonalRosterData({
    required this.year,
    required this.month,
    required this.person,
    required this.shifts,
    required this.dayShiftDays,
    required this.leaves,
  });

  final int year;
  final int month;
  final Person person;
  final List<PersonalShift> shifts;

  /// 7A (gündüz mesaisi) günleri, sıralı.
  final List<int> dayShiftDays;

  /// İzin türü → günler (yalnız boş olmayanlar).
  final Map<LeaveType, List<int>> leaves;

  int get weekendShifts => shifts.where((s) => s.isWeekend).length;

  int get leaveDayCount => leaves.values.fold(0, (s, d) => s + d.length);

  /// Gün → izin türü.
  Map<int, LeaveType> get leaveByDay => {
    for (final e in leaves.entries)
      for (final d in e.value) d: e.key,
  };

  String get monthLabel => '${turkishMonthNames[month - 1]} $year';
}

/// Bir kişinin aylık nöbetlerini, her nöbet günündeki tüm hemşire ve
/// radyoloji nöbetçileriyle birlikte hazırlar (saf Dart). [text] WhatsApp
/// gibi mesajlaşma uygulamalarına uygun düz metin üretir; PDF de [build]
/// verisini kullanır.
class PersonalRoster {
  const PersonalRoster._();

  static PersonalRosterData build({
    required MonthPlan plan,
    required Person person,
    required Iterable<Person> people,
    Iterable<DayShift> dayShifts = const [],
    Set<int> weekendDays = const {},
  }) {
    final names = {for (final p in people) p.id: p.name};
    String name(String id) => names[id] ?? 'Silinmiş kişi';

    final shifts = <PersonalShift>[
      for (var d = 1; d <= plan.daysInMonth; d++)
        if (plan.assignments[d] case final a? when a.includes(person.id))
          PersonalShift(
            day: d,
            shift: a.isSecondaryTech(person.id) ? '16B' : '24',
            nurses: a.nurseIds.map(name).toList(),
            techs: [
              if (a.techId case final id?)
                a.tech16bId != null ? '${name(id)} (24)' : name(id),
              if (a.tech16bId case final id?) '${name(id)} (16B)',
            ],
            isWeekend: weekendDays.contains(d),
          ),
    ];
    return PersonalRosterData(
      year: plan.year,
      month: plan.month,
      person: person,
      shifts: shifts,
      dayShiftDays: [
        for (final s in dayShifts)
          if (s.personId == person.id) s.day,
      ]..sort(),
      leaves: {
        for (final type in LeaveType.values)
          if (plan.leaveOf(person.id, type).isNotEmpty)
            type: [...plan.leaveOf(person.id, type)]..sort(),
      },
    );
  }

  static String text({
    required MonthPlan plan,
    required Person person,
    required Iterable<Person> people,
    Iterable<DayShift> dayShifts = const [],
  }) {
    final data = build(
      plan: plan,
      person: person,
      people: people,
      dayShifts: dayShifts,
    );
    final lines = <String>['${person.name} · ${data.monthLabel} nöbetleri', ''];

    if (data.shifts.isEmpty) {
      lines.add('Bu ay nöbet yok.');
    }
    for (final s in data.shifts) {
      lines
        ..add(
          '• ${formatDayMonthWeekday(plan.year, plan.month, s.day)} — '
          '${s.shift}',
        )
        ..add('  Hemşire: ${s.nurses.join(', ')}');
      if (s.techs.isNotEmpty) {
        lines.add('  Radyoloji: ${s.techs.join(', ')}');
      }
    }

    if (data.dayShiftDays.isNotEmpty) {
      lines
        ..add('')
        ..add(
          '7A (gündüz): ${data.dayShiftDays.join(', ')} '
          '${turkishMonthNames[plan.month - 1]}',
        );
    }

    if (data.leaves.isNotEmpty) {
      lines
        ..add('')
        ..addAll([
          for (final e in data.leaves.entries)
            '${e.key.label}: ${ranges(e.value, plan.month)}',
        ]);
    }

    lines
      ..add('')
      ..add('Toplam: ${data.shifts.length} nöbet');
    return lines.join('\n');
  }

  /// [1,2,3,7] → "1–3, 7 Ekim"
  static String ranges(List<int> days, int month) {
    final sorted = [...days]..sort();
    final parts = <String>[];
    var start = sorted.first;
    var prev = start;
    void flush() => parts.add(start == prev ? '$start' : '$start–$prev');
    for (final d in sorted.skip(1)) {
      if (d == prev + 1) {
        prev = d;
        continue;
      }
      flush();
      start = d;
      prev = d;
    }
    flush();
    return '${parts.join(', ')} ${turkishMonthNames[month - 1]}';
  }
}
