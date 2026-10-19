import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../data/providers.dart';
import '../../logic/past_roster_entry.dart';
import '../../logic/turkish_collation.dart';
import '../../models/models.dart';
import '../../shared/widgets/month_selector.dart';
import '../month/month_plan_controller.dart';
import '../people/people_controller.dart';

/// Uygulamadan önce tutulmuş listeleri girme ekranı: ay ve hemşire seçilir,
/// kişinin nöbet tuttuğu günler takvimden işaretlenir. Girilen günler o
/// ayın listesine yazılır; yıllık özet ve yıl içi denge bunları kullanır.
class PastRosterPage extends ConsumerStatefulWidget {
  const PastRosterPage({super.key, required this.initialYear});

  final int initialYear;

  @override
  ConsumerState<PastRosterPage> createState() => _PastRosterPageState();
}

class _PastRosterPageState extends ConsumerState<PastRosterPage> {
  late DateTime _month = DateTime(widget.initialYear);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final plan = ref
        .watch(monthPlanRepositoryProvider)
        .get(_month.year, _month.month);
    // Ekran dönünce sayılar yenilensin diye kişiler izlenir.
    final nurses =
        ref.watch(peopleProvider).where((p) => p.role == Role.nurse).toList()
          ..sort((a, b) => compareTurkish(a.name, b.name));
    final assignments = plan?.assignments ?? const <int, DayAssignment>{};
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    final counts = PastRosterEntry.nurseCounts(assignments);
    final filled = counts.length;

    return Scaffold(
      appBar: AppBar(title: const Text('Eski listeleri gir')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          MonthSelector(
            month: _month,
            onChanged: (m) =>
                setState(() => _month = DateTime(m.year, m.month)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              'Hemşireye dokunup o ay nöbet tuttuğu günleri işaretleyin. '
              'Girilenler bu ayın listesine yazılır; yıllık özet ve yıl içi '
              'denge hesabı bunları kullanır.',
              style: theme.textTheme.bodyMedium,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              'Hemşire girilmiş gün: $filled / $daysInMonth',
              style: theme.textTheme.labelLarge,
            ),
          ),
          for (final p in nurses)
            ListTile(
              key: ValueKey('past-${p.id}'),
              leading: const Icon(Icons.person_outline),
              title: Text(p.name),
              subtitle: Text(
                [
                  p.isChargeNurse ? 'Sorumlu hemşire' : 'Hemşire',
                  if (!p.isActive) 'pasif',
                ].join(' · '),
              ),
              trailing: Text(
                '${PastRosterEntry.nurseDaysOf(assignments, p.id).length} nöbet',
                style: theme.textTheme.titleSmall,
              ),
              onTap: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => _PersonDaysPage(person: p, month: _month),
                  ),
                );
                if (mounted) setState(() {});
              },
            ),
          if (nurses.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('Önce Kişiler ekranından hemşire ekleyin.'),
            ),
        ],
      ),
    );
  }
}

/// Bir hemşirenin seçili aydaki nöbet günlerini işaretleme takvimi. Her
/// dokunuş hemen kaydedilir; günün altında o güne girilmiş hemşire sayısı
/// görünür.
class _PersonDaysPage extends ConsumerStatefulWidget {
  const _PersonDaysPage({required this.person, required this.month});

  final Person person;
  final DateTime month;

  @override
  ConsumerState<_PersonDaysPage> createState() => _PersonDaysPageState();
}

class _PersonDaysPageState extends ConsumerState<_PersonDaysPage> {
  Future<void> _toggle(int day) async {
    final repo = ref.read(monthPlanRepositoryProvider);
    final month = widget.month;
    final plan = await repo.getOrCreate(month.year, month.month);
    final days = PastRosterEntry.nurseDaysOf(
      plan.assignments,
      widget.person.id,
    );
    if (!days.remove(day)) days.add(day);
    final assignments = PastRosterEntry.setNurseDays(
      plan.assignments,
      personId: widget.person.id,
      days: days,
      daysInMonth: plan.daysInMonth,
    );
    await repo.save(
      plan.copyWith(
        assignments: assignments,
        // Eski liste yalnız hemşirelerle girilir.
        nurseOnly: plan.hasRoster ? null : true,
        generatedAt: plan.generatedAt ?? DateTime.now(),
      ),
    );
    // Açık ay bu aysa diğer ekranlar yeni listeyi okusun.
    ref.invalidate(monthPlanProvider);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final month = widget.month;
    final plan = ref
        .read(monthPlanRepositoryProvider)
        .get(month.year, month.month);
    final assignments = plan?.assignments ?? const <int, DayAssignment>{};
    final selected = PastRosterEntry.nurseDaysOf(assignments, widget.person.id);
    final counts = PastRosterEntry.nurseCounts(assignments);
    final firstDay = DateTime(month.year, month.month);
    final lastDay = DateTime(month.year, month.month + 1, 0);

    Widget dayCell(DateTime day) {
      final isSelected = selected.contains(day.day);
      final count = counts[day.day] ?? 0;
      final weekend =
          day.weekday == DateTime.saturday || day.weekday == DateTime.sunday;
      return Container(
        key: ValueKey('past-day-${day.day}'),
        margin: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: isSelected ? scheme.primary : null,
          borderRadius: BorderRadius.circular(8),
          border: isSelected ? null : Border.all(color: scheme.outlineVariant),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '${day.day}',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: isSelected
                    ? scheme.onPrimary
                    : weekend
                    ? scheme.primary
                    : null,
              ),
            ),
            Text(
              count == 0 ? '' : '$count hem.',
              style: theme.textTheme.labelSmall?.copyWith(
                color: isSelected
                    ? scheme.onPrimary
                    : count >= 2
                    ? scheme.onSurfaceVariant
                    : scheme.error,
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(widget.person.name)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            DateFormat.yMMMM('tr_TR').format(firstDay),
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            'Nöbet tuttuğu günlere dokunun; tekrar dokununca kaldırılır. '
            'Seçili: ${selected.length} gün',
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
            rowHeight: 56,
            calendarStyle: const CalendarStyle(outsideDaysVisible: false),
            onDaySelected: (day, _) => _toggle(day.day),
            calendarBuilders: CalendarBuilders(
              prioritizedBuilder: (context, day, _) => dayCell(day),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Günün altındaki sayı, o güne girilmiş hemşire sayısıdır '
            '(2\'den azsa kırmızı).',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
