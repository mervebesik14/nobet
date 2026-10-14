import '../models/month_plan.dart';
import '../models/person.dart';
import 'day_shift_planner.dart';
import 'turkish_dates.dart';

/// Bir kişinin aylık nöbetlerini, her nöbet günündeki tüm hemşire ve
/// radyoloji nöbetçileriyle birlikte paylaşılabilir metne çevirir (saf
/// Dart). WhatsApp gibi mesajlaşma uygulamalarına uygun düz metindir.
class PersonalRoster {
  const PersonalRoster._();

  static String text({
    required MonthPlan plan,
    required Person person,
    required Iterable<Person> people,
    Map<int, DayShift> dayShifts = const {},
  }) {
    final names = {for (final p in people) p.id: p.name};
    String name(String id) => names[id] ?? 'Silinmiş kişi';
    final month = '${turkishMonthNames[plan.month - 1]} ${plan.year}';

    final shiftDays = [
      for (var d = 1; d <= plan.daysInMonth; d++)
        if (plan.assignments[d]?.includes(person.id) ?? false) d,
    ];
    final lines = <String>['${person.name} · $month nöbetleri', ''];

    if (shiftDays.isEmpty) {
      lines.add('Bu ay nöbet yok.');
    }
    for (final d in shiftDays) {
      final a = plan.assignments[d]!;
      final twoTechs = a.tech16bId != null;
      final own = a.isSecondaryTech(person.id) ? '16B' : '24';
      lines
        ..add('• ${formatDayMonthWeekday(plan.year, plan.month, d)} — $own')
        ..add('  Hemşire: ${a.nurseIds.map(name).join(', ')}');
      final techs = [
        if (a.techId case final id?) twoTechs ? '${name(id)} (24)' : name(id),
        if (a.tech16bId case final id?) '${name(id)} (16B)',
      ];
      if (techs.isNotEmpty) {
        lines.add('  Radyoloji: ${techs.join(', ')}');
      }
    }

    final dayShiftDays = [
      for (final s in dayShifts.values)
        if (s.personId == person.id) s.day,
    ]..sort();
    if (dayShiftDays.isNotEmpty) {
      lines
        ..add('')
        ..add(
          '7A (gündüz): ${dayShiftDays.join(', ')} '
          '${turkishMonthNames[plan.month - 1]}',
        );
    }

    final leaves = [
      for (final type in LeaveType.values)
        if (plan.leaveOf(person.id, type).isNotEmpty)
          '${type.label}: ${_ranges(plan.leaveOf(person.id, type), plan.month)}',
    ];
    if (leaves.isNotEmpty) {
      lines
        ..add('')
        ..addAll(leaves);
    }

    lines
      ..add('')
      ..add('Toplam: ${shiftDays.length} nöbet');
    return lines.join('\n');
  }

  /// [1,2,3,7] → "1–3, 7 Ekim"
  static String _ranges(List<int> days, int month) {
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
