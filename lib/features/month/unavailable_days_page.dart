import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../models/models.dart';
import '../holidays/holidays_controller.dart';
import 'month_plan_controller.dart';
import '../../shared/app_colors.dart';

/// Bir kişinin seçili aydaki istenmeyen günlerini ve yıllık izinlerini
/// takvimden seçme ekranı. İki sekme: istenmeyen günler ve yıllık izin.
class UnavailableDaysPage extends ConsumerStatefulWidget {
  const UnavailableDaysPage({super.key, required this.person});

  final Person person;

  @override
  ConsumerState<UnavailableDaysPage> createState() =>
      _UnavailableDaysPageState();
}

class _UnavailableDaysPageState extends ConsumerState<UnavailableDaysPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this)
    ..addListener(() => setState(() {}));

  Person get person => widget.person;

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final plan = ref.watch(monthPlanProvider);
    final controller = ref.read(monthPlanProvider.notifier);
    final unavailable = plan.unavailableDaysOf(person.id).toSet();
    final leave = plan.annualLeaveOf(person.id).toSet();
    final onLeaveTab = _tabs.index == 1;
    final current = onLeaveTab ? leave : unavailable;

    return Scaffold(
      appBar: AppBar(
        title: Text(person.name),
        actions: [
          if (current.isNotEmpty && !plan.isLocked)
            TextButton(
              onPressed: () => onLeaveTab
                  ? controller.clearLeave(person.id)
                  : controller.clearUnavailable(person.id),
              child: const Text('Temizle'),
            ),
        ],
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'İstenmeyen günler'),
            Tab(text: 'Yıllık izin'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _CalendarEditor(
            person: person,
            mode: _EditorMode.unavailable,
            selected: unavailable,
            showOvertime: true,
          ),
          _CalendarEditor(
            person: person,
            mode: _EditorMode.leave,
            selected: leave,
            showOvertime: false,
          ),
        ],
      ),
    );
  }
}

enum _EditorMode { unavailable, leave }

/// İki sekmede ortak kullanılan takvim düzenleyici.
class _CalendarEditor extends ConsumerWidget {
  const _CalendarEditor({
    required this.person,
    required this.mode,
    required this.selected,
    required this.showOvertime,
  });

  final Person person;
  final _EditorMode mode;
  final Set<int> selected;
  final bool showOvertime;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plan = ref.watch(monthPlanProvider);
    final controller = ref.read(monthPlanProvider.notifier);
    final holidays = {
      for (final h in ref.watch(holidaysProvider))
        if (h.date.year == plan.year && h.date.month == plan.month)
          h.date.day: h,
    };
    final firstDay = DateTime(plan.year, plan.month);
    final lastDay = DateTime(plan.year, plan.month, plan.daysInMonth);
    final theme = Theme.of(context);
    final isLeave = mode == _EditorMode.leave;

    void toggle(int day) {
      if (plan.isLocked) return;
      if (isLeave) {
        controller.toggleLeave(person.id, day);
      } else {
        controller.toggleUnavailable(person.id, day);
      }
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          '${DateFormat.yMMMM('tr_TR').format(firstDay)} · ${person.role.label}',
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 4),
        Text(
          plan.isLocked
              ? (isLeave
                    ? 'Bu ay kilitli; yıllık izinler değiştirilemez.'
                    : 'Bu ay kilitli; istenmeyen günler değiştirilemez.')
              : (isLeave
                    ? 'Yıllık izin günlerine dokunun. İzin günü nöbet '
                          'verilmez ve gereken saatten düşülür. '
                          'Seçili: ${selected.length} gün'
                    : 'Nöbet istemediği günlere dokunun. '
                          'Seçili: ${selected.length} gün'),
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
          selectedDayPredicate: (day) => selected.contains(day.day),
          onDaySelected: (day, _) => toggle(day.day),
          calendarBuilders: CalendarBuilders(
            prioritizedBuilder: (context, day, _) => _DayCell(
              day: day.day,
              isSelected: selected.contains(day.day),
              isLeave: isLeave,
              holiday: holidays[day.day],
              isWeekend:
                  day.weekday == DateTime.saturday ||
                  day.weekday == DateTime.sunday,
            ),
          ),
        ),
        const SizedBox(height: 16),
        _Legend(isLeave: isLeave),
        if (showOvertime) ...[
          const Divider(height: 32),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.more_time),
            title: const Text('Fazla mesai istiyor'),
            subtitle: const Text(
              'Nöbet sayısı diğerlerinden birkaç fazla olabilir.',
            ),
            value: plan.wantsOvertime(person.id),
            onChanged: plan.isLocked
                ? null
                : (v) => controller.setOvertime(person.id, v),
          ),
        ],
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
    );
  }
}

/// Gün hücresi renkleri: seçili > tatil > hafta sonu > normal.
({Color background, Color foreground})? _cellColors(
  ColorScheme scheme, {
  required bool isSelected,
  required bool isLeave,
  required bool isHoliday,
  required bool isWeekend,
}) {
  if (isSelected) {
    return isLeave
        ? (background: scheme.leaveColor, foreground: Colors.white)
        : (background: scheme.error, foreground: scheme.onError);
  }
  if (isHoliday) {
    return (background: scheme.holidayTint, foreground: scheme.onSurface);
  }
  if (isWeekend) {
    return (background: scheme.weekendTint, foreground: scheme.onSurface);
  }
  return null;
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.isSelected,
    required this.isLeave,
    required this.holiday,
    required this.isWeekend,
  });

  final int day;
  final bool isSelected;
  final bool isLeave;
  final Holiday? holiday;
  final bool isWeekend;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final colors = _cellColors(
      scheme,
      isSelected: isSelected,
      isLeave: isLeave,
      isHoliday: holiday != null,
      isWeekend: isWeekend,
    );
    return Container(
      margin: const EdgeInsets.all(4),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colors?.background,
        borderRadius: BorderRadius.circular(8),
        // Tatil olan seçili gün de tatil olduğu anlaşılsın.
        border: holiday != null && isSelected
            ? Border.all(color: const Color(0xFFE0A030), width: 2)
            : null,
      ),
      child: Text(
        '$day',
        style: TextStyle(
          color: colors?.foreground,
          fontWeight: isSelected ? FontWeight.bold : null,
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.isLeave});

  final bool isLeave;

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
        isLeave
            ? item(scheme.leaveColor, 'Yıllık izin')
            : item(scheme.error, 'İstemiyor'),
        item(scheme.holidayTint, 'Resmi tatil'),
        item(scheme.weekendTint, 'Hafta sonu'),
      ],
    );
  }
}
