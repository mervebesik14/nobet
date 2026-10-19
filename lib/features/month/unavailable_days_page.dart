import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../models/models.dart';
import '../holidays/holidays_controller.dart';
import '../../shared/widgets/month_selector.dart';
import 'month_plan_controller.dart';
import '../../shared/app_colors.dart';

/// Bir kişinin seçili aydaki istenmeyen günlerini ve izinlerini düzenleme
/// ekranı. Sekmeler: istenmeyen günler, (sorumlu hemşirede) nöbet günleri,
/// yıllık izin, şua izni.
class UnavailableDaysPage extends ConsumerStatefulWidget {
  const UnavailableDaysPage({super.key, required this.person});

  final Person person;

  @override
  ConsumerState<UnavailableDaysPage> createState() =>
      _UnavailableDaysPageState();
}

/// Sekme: istenmeyen günler, sorumlu hemşirenin nöbet günleri ya da bir
/// izin türü.
sealed class _Tab {
  const _Tab();
}

class _UnavailableTab extends _Tab {
  const _UnavailableTab();
}

class _RequestedTab extends _Tab {
  const _RequestedTab();
}

class _LeaveTab extends _Tab {
  const _LeaveTab(this.type);
  final LeaveType type;
}

class _UnavailableDaysPageState extends ConsumerState<UnavailableDaysPage>
    with SingleTickerProviderStateMixin {
  Person get person => widget.person;

  /// Nöbet günleri sekmesi yalnızca sorumlu hemşirede görünür.
  late final List<_Tab> _tabList = [
    const _UnavailableTab(),
    if (person.isChargeNurse && person.role == Role.nurse)
      const _RequestedTab(),
    for (final type in LeaveType.values) _LeaveTab(type),
  ];

  late final TabController _tabs = TabController(
    length: _tabList.length,
    vsync: this,
  )..addListener(() => setState(() {}));

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final plan = ref.watch(monthPlanProvider);
    final controller = ref.read(monthPlanProvider.notifier);

    // Aktif sekmedeki verinin varlığı ve "Temizle" eylemi.
    final (hasData, onClear) = switch (_tabList[_tabs.index]) {
      _UnavailableTab() => (
        plan.unavailableDaysOf(person.id).isNotEmpty,
        () => controller.clearUnavailable(person.id),
      ),
      _RequestedTab() => (
        plan.requestedShiftsOf(person.id).isNotEmpty,
        () => controller.clearRequestedShifts(person.id),
      ),
      _LeaveTab(:final type) => (
        plan.leaveOf(person.id, type).isNotEmpty,
        () => controller.clearLeave(person.id, type),
      ),
    };

    return Scaffold(
      appBar: AppBar(
        title: Text(person.name),
        actions: [
          if (hasData && !plan.isLocked)
            TextButton(onPressed: onClear, child: const Text('Temizle')),
        ],
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: [
            for (final tab in _tabList)
              Tab(
                text: switch (tab) {
                  _UnavailableTab() => 'İstenmeyen günler',
                  _RequestedTab() => 'Nöbet günleri',
                  _LeaveTab(:final type) => type.label,
                },
              ),
          ],
        ),
      ),
      body: Column(
        children: [
          // Kişinin takviminde aylar arasında gezinme; Ay Planı'nın seçili
          // ayı da değişir.
          MonthSelector(
            month: DateTime(plan.year, plan.month),
            onChanged: ref.read(planMonthProvider.notifier).select,
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                for (final tab in _tabList)
                  switch (tab) {
                    _UnavailableTab() => _CalendarEditor(person: person),
                    _RequestedTab() => _CalendarEditor(
                      person: person,
                      requested: true,
                    ),
                    _LeaveTab(:final type) => _LeaveEditor(
                      person: person,
                      type: type,
                    ),
                  },
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Takvimden tek tek gün seçme sekmesi. [requested] ise sorumlu hemşirenin
/// nöbet tutacağı günler; değilse istenmeyen günler (+ fazla mesai).
class _CalendarEditor extends ConsumerWidget {
  const _CalendarEditor({required this.person, this.requested = false});

  final Person person;
  final bool requested;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plan = ref.watch(monthPlanProvider);
    final controller = ref.read(monthPlanProvider.notifier);
    final selected =
        (requested
                ? plan.requestedShiftsOf(person.id)
                : plan.unavailableDaysOf(person.id))
            .toSet();
    final holidays = {
      for (final h in ref.watch(holidaysProvider))
        if (h.date.year == plan.year && h.date.month == plan.month)
          h.date.day: h,
    };
    final firstDay = DateTime(plan.year, plan.month);
    final lastDay = DateTime(plan.year, plan.month, plan.daysInMonth);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final mark = requested ? scheme.primary : scheme.error;
    final onMark = requested ? scheme.onPrimary : scheme.onError;

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
              ? 'Bu ay kilitli; ${requested ? 'nöbet günleri' : 'istenmeyen günler'} '
                    'değiştirilemez.'
              : requested
              ? 'Nöbet tutacağı günlere dokunun; liste oluşturulurken bu '
                    'günlere nöbet yazılır. Seçilmeyen günlerde 24 yazılmaz; '
                    'mesai günlerinde 7A çalışır. '
                    'Seçili: ${selected.length} gün'
              : 'Nöbet istemediği günlere dokunun. Seçili: ${selected.length} gün',
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
          onDaySelected: (day, _) {
            if (plan.isLocked) return;
            if (requested) {
              controller.toggleRequestedShift(person.id, day.day);
            } else {
              controller.toggleUnavailable(person.id, day.day);
            }
          },
          calendarBuilders: CalendarBuilders(
            prioritizedBuilder: (context, day, _) => _DayCell(
              day: day.day,
              background: selected.contains(day.day) ? mark : null,
              foreground: selected.contains(day.day) ? onMark : null,
              holiday: holidays[day.day],
              isWeekend:
                  day.weekday == DateTime.saturday ||
                  day.weekday == DateTime.sunday,
            ),
          ),
        ),
        const SizedBox(height: 16),
        _Legend(items: [(mark, requested ? 'Nöbet tutacak' : 'İstemiyor')]),
        if (!requested) ...[
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
        _HolidayList(holidays: holidays.values),
      ],
    );
  }
}

/// İzin sekmesi (yıllık / şua): başlangıç–bitiş tarih aralığı ile izin girme.
class _LeaveEditor extends ConsumerStatefulWidget {
  const _LeaveEditor({required this.person, required this.type});

  final Person person;
  final LeaveType type;

  @override
  ConsumerState<_LeaveEditor> createState() => _LeaveEditorState();
}

class _LeaveEditorState extends ConsumerState<_LeaveEditor> {
  DateTime? _rangeStart;
  DateTime? _rangeEnd;

  Person get person => widget.person;
  LeaveType get type => widget.type;

  /// Sıralı gün listesini bitişik aralıklara ayırır: [1,2,3,7] → [(1,3),(7,7)].
  List<(int, int)> _ranges(List<int> days) {
    if (days.isEmpty) return const [];
    final sorted = [...days]..sort();
    final out = <(int, int)>[];
    var start = sorted.first;
    var prev = sorted.first;
    for (final d in sorted.skip(1)) {
      if (d == prev + 1) {
        prev = d;
      } else {
        out.add((start, prev));
        start = d;
        prev = d;
      }
    }
    out.add((start, prev));
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final plan = ref.watch(monthPlanProvider);
    final controller = ref.read(monthPlanProvider.notifier);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final days = plan.leaveOf(person.id, type).toSet();
    final holidays = {
      for (final h in ref.watch(holidaysProvider))
        if (h.date.year == plan.year && h.date.month == plan.month)
          h.date.day: h,
    };
    final firstDay = DateTime(plan.year, plan.month);
    final lastDay = DateTime(plan.year, plan.month, plan.daysInMonth);
    final monthName = DateFormat.MMMM('tr_TR').format(firstDay);
    final locked = plan.isLocked;
    final start = _rangeStart;
    final canAdd = !locked && start != null;
    final dayMonth = DateFormat('d MMMM', 'tr_TR');

    String rangeText(int a, int b) =>
        a == b ? '$a $monthName' : '$a–$b $monthName';

    String selectionText(DateTime a, DateTime b) {
      if (isSameDay(a, b)) return dayMonth.format(a);
      if (a.year == b.year && a.month == b.month) {
        return '${a.day}–${dayMonth.format(b)}';
      }
      return '${dayMonth.format(a)} – ${dayMonth.format(b)}';
    }

    Future<void> add() async {
      final s = start!;
      final e = _rangeEnd ?? s;
      final skipped = await controller.addLeaveDates(person.id, type, s, e);
      if (!context.mounted) return;
      setState(() {
        _rangeStart = null;
        _rangeEnd = null;
      });
      final monthYear = DateFormat.yMMMM('tr_TR');
      final multi = s.year != e.year || s.month != e.month;
      final message = skipped.isNotEmpty
          ? '${skipped.map(monthYear.format).join(', ')} kilitli olduğu için '
                'o aya izin yazılamadı.'
          : multi
          ? '${type.label} eklendi: ${selectionText(s, e)}. Diğer ayın günleri '
                'o ayın planına yazıldı.'
          : null;
      if (message != null) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(message)));
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
          locked
              ? 'Bu ay kilitli; ${type.label.toLowerCase()} değiştirilemez.'
              : 'Başlangıç ve bitiş gününü seçin, sonra "İzin ekle"ye dokunun. '
                    'İzin sonraki aya taşıyorsa başlangıcı seçip yukarıdan '
                    'sonraki aya geçin ve bitişi orada seçin. '
                    'İzin günlerinde nöbet verilmez ve gereken saatten düşülür. '
                    '${switch (type) {
                      LeaveType.annual => 'İzinden önceki son nöbet, izinden önceki son iş '
                          'gününden bir önceki gündür (izin Pazartesi '
                          'başlıyorsa Perşembe). İzinden sonra ilk iş günü '
                          'nöbete girebilir.',
                      LeaveType.radiation => 'Kişi iznin bittiği günden sonra nöbete girebilir.',
                      LeaveType.sick => 'Kişi raporun bittiği günden sonra nöbete girebilir.',
                    }}',
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
          // Aralık elle tutulur; başlangıç önceki ayda kalabilir.
          rangeSelectionMode: RangeSelectionMode.toggledOff,
          rangeStartDay: _rangeStart,
          rangeEndDay: _rangeEnd,
          calendarStyle: CalendarStyle(
            outsideDaysVisible: false,
            rangeHighlightColor: scheme.leaveBackground(type),
            withinRangeTextStyle: TextStyle(color: scheme.onSurface),
            rangeStartDecoration: BoxDecoration(
              color: scheme.leaveInk(type),
              shape: BoxShape.circle,
            ),
            rangeEndDecoration: BoxDecoration(
              color: scheme.leaveInk(type),
              shape: BoxShape.circle,
            ),
          ),
          onDaySelected: locked
              ? null
              : (day, _) => setState(() {
                  final d = DateTime(day.year, day.month, day.day);
                  final s = _rangeStart;
                  if (s == null || _rangeEnd != null) {
                    _rangeStart = d;
                    _rangeEnd = null;
                  } else if (d.isBefore(s)) {
                    _rangeStart = d;
                    _rangeEnd = s;
                  } else {
                    _rangeEnd = d;
                  }
                }),
          calendarBuilders: CalendarBuilders(
            // Kayıtlı izin günleri her zaman izin renginde; seçim aralığı
            // yalnızca henüz kaydedilmemiş günlerde görünür.
            prioritizedBuilder: (context, day, _) => days.contains(day.day)
                ? _DayCell(
                    day: day.day,
                    background: scheme.leaveInk(type),
                    foreground: Colors.white,
                    holiday: holidays[day.day],
                    isWeekend:
                        day.weekday == DateTime.saturday ||
                        day.weekday == DateTime.sunday,
                  )
                : null,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Text(
                start == null
                    ? 'Aralık seçilmedi'
                    : _rangeEnd == null
                    ? 'Başlangıç: ${dayMonth.format(start)} · bitişi seçin'
                    : 'Seçilen: ${selectionText(start, _rangeEnd!)}',
                style: theme.textTheme.bodyMedium,
              ),
            ),
            FilledButton.icon(
              onPressed: canAdd ? add : null,
              icon: const Icon(Icons.add),
              label: const Text('İzin ekle'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _Legend(items: [(scheme.leaveInk(type), type.label)]),
        if (days.isNotEmpty) ...[
          const Divider(height: 32),
          Text(
            '${type.label} günleri (${days.length} gün)',
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final (a, b) in _ranges(days.toList()))
                Chip(
                  label: Text(rangeText(a, b)),
                  onDeleted: locked
                      ? null
                      : () =>
                            controller.removeLeaveRange(person.id, type, a, b),
                ),
            ],
          ),
        ],
        _HolidayList(holidays: holidays.values),
      ],
    );
  }
}

class _HolidayList extends StatelessWidget {
  const _HolidayList({required this.holidays});

  final Iterable<Holiday> holidays;

  @override
  Widget build(BuildContext context) {
    if (holidays.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        for (final h in holidays)
          Text(
            '${h.date.day} ${DateFormat.MMMM('tr_TR').format(h.date)}: '
            '${h.name}${h.isHalfDay ? ' (yarım gün)' : ''}',
            style: theme.textTheme.bodySmall,
          ),
      ],
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.background,
    required this.foreground,
    required this.holiday,
    required this.isWeekend,
  });

  final int day;
  final Color? background;
  final Color? foreground;
  final Holiday? holiday;
  final bool isWeekend;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final selected = background != null;
    final bg =
        background ??
        (holiday != null
            ? scheme.holidayTint
            : isWeekend
            ? scheme.weekendTint
            : null);
    return Container(
      margin: const EdgeInsets.all(4),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        // Tatil olan seçili gün de tatil olduğu anlaşılsın.
        border: holiday != null && selected
            ? Border.all(color: const Color(0xFFE0A030), width: 2)
            : null,
      ),
      child: Text(
        '$day',
        style: TextStyle(
          color: foreground ?? (selected ? Colors.white : null),
          fontWeight: selected ? FontWeight.bold : null,
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.items});

  /// Ekrana özel ilk öğeler; sonrasına tatil ve hafta sonu eklenir.
  final List<(Color, String)> items;

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
        for (final (color, label) in items) item(color, label),
        item(scheme.holidayTint, 'Resmi tatil'),
        item(scheme.weekendTint, 'Hafta sonu'),
      ],
    );
  }
}
