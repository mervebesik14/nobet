import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../models/models.dart';
import '../holidays/holidays_controller.dart';
import 'month_plan_controller.dart';

/// Bir kişinin seçili aydaki istenmeyen günlerini takvimden seçme ekranı.
class UnavailableDaysPage extends ConsumerWidget {
  const UnavailableDaysPage({super.key, required this.person});

  final Person person;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plan = ref.watch(monthPlanProvider);
    final controller = ref.read(monthPlanProvider.notifier);
    final unavailable = plan.unavailableDaysOf(person.id).toSet();
    final holidays = {
      for (final h in ref.watch(holidaysProvider))
        if (h.date.year == plan.year && h.date.month == plan.month)
          h.date.day: h,
    };
    final firstDay = DateTime(plan.year, plan.month);
    final lastDay = DateTime(plan.year, plan.month, plan.daysInMonth);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(person.name),
        actions: [
          if (unavailable.isNotEmpty && !plan.isLocked)
            TextButton(
              onPressed: () => controller.clearUnavailable(person.id),
              child: const Text('Temizle'),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            '${DateFormat.yMMMM('tr_TR').format(firstDay)} · '
            '${person.role.label}',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            plan.isLocked
                ? 'Bu ay kilitli; istenmeyen günler değiştirilemez.'
                : 'Nöbet istemediği günlere dokunun. '
                      'Seçili: ${unavailable.length} gün',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 8),
          TableCalendar<void>(
            locale: 'tr_TR',
            firstDay: firstDay,
            lastDay: lastDay,
            focusedDay: firstDay,
            startingDayOfWeek: StartingDayOfWeek.monday,
            availableGestures: AvailableGestures.none,
            headerVisible: false,
            calendarStyle: const CalendarStyle(outsideDaysVisible: false),
            selectedDayPredicate: (day) => unavailable.contains(day.day),
            onDaySelected: (day, _) {
              if (!plan.isLocked) {
                controller.toggleUnavailable(person.id, day.day);
              }
            },
            calendarBuilders: CalendarBuilders(
              prioritizedBuilder: (context, day, _) => _DayCell(
                day: day.day,
                isUnavailable: unavailable.contains(day.day),
                holiday: holidays[day.day],
                isWeekend:
                    day.weekday == DateTime.saturday ||
                    day.weekday == DateTime.sunday,
              ),
            ),
          ),
          const SizedBox(height: 16),
          const _Legend(),
          if (holidays.isNotEmpty) ...[
            const SizedBox(height: 16),
            for (final h in holidays.values)
              Text(
                '${h.date.day} ${DateFormat.MMMM('tr_TR').format(h.date)}: '
                '${h.name}${h.isHalfDay ? ' (yarım gün)' : ''}',
                style: theme.textTheme.bodySmall,
              ),
          ],
        ],
      ),
    );
  }
}

/// Gün hücresi renkleri: istenmeyen > tatil > hafta sonu > normal.
({Color background, Color foreground})? _cellColors(
  ColorScheme scheme, {
  required bool isUnavailable,
  required bool isHoliday,
  required bool isWeekend,
}) {
  if (isUnavailable) {
    return (background: scheme.error, foreground: scheme.onError);
  }
  if (isHoliday) {
    return (
      background: scheme.tertiaryContainer,
      foreground: scheme.onTertiaryContainer,
    );
  }
  if (isWeekend) {
    return (
      background: scheme.secondaryContainer,
      foreground: scheme.onSecondaryContainer,
    );
  }
  return null;
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.isUnavailable,
    required this.holiday,
    required this.isWeekend,
  });

  final int day;
  final bool isUnavailable;
  final Holiday? holiday;
  final bool isWeekend;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final colors = _cellColors(
      scheme,
      isUnavailable: isUnavailable,
      isHoliday: holiday != null,
      isWeekend: isWeekend,
    );
    return Container(
      margin: const EdgeInsets.all(4),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colors?.background,
        borderRadius: BorderRadius.circular(8),
        // Tatil olan istenmeyen gün de tatil olduğu anlaşılsın.
        border: holiday != null && isUnavailable
            ? Border.all(color: scheme.tertiary, width: 2)
            : null,
      ),
      child: Text(
        '$day',
        style: TextStyle(
          color: colors?.foreground,
          fontWeight: isUnavailable ? FontWeight.bold : null,
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget item(Color color, String label) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 6),
        Text(label),
      ],
    );
    return Wrap(
      spacing: 16,
      runSpacing: 8,
      children: [
        item(scheme.error, 'İstemiyor'),
        item(scheme.tertiaryContainer, 'Resmi tatil'),
        item(scheme.secondaryContainer, 'Hafta sonu'),
      ],
    );
  }
}
