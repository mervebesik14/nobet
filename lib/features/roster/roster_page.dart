import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../data/providers.dart';
import '../../logic/roster_generator.dart';
import '../../logic/roster_summary.dart';
import '../../logic/turkish_dates.dart';
import '../holidays/holidays_controller.dart';
import '../month/month_plan_controller.dart';
import '../people/people_controller.dart';
import 'roster_flow.dart';
import 'roster_table.dart';
import 'summary_table.dart';

/// Seçili ayın nöbet listesi ve özet tablosu.
class RosterPage extends ConsumerWidget {
  const RosterPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plan = ref.watch(monthPlanProvider);
    final people = ref.watch(peopleProvider);
    final settings = ref.watch(rosterSettingsProvider);
    final holidays = ref
        .watch(holidaysProvider)
        .where((h) => h.date.year == plan.year && h.date.month == plan.month)
        .toList();
    final controller = ref.read(monthPlanProvider.notifier);
    final theme = Theme.of(context);

    final summary = RosterSummary.build(
      year: plan.year,
      month: plan.month,
      assignments: plan.assignments,
      people: people,
      holidays: holidays,
      settings: settings,
    );
    final missingDays = [
      for (var d = 1; d <= plan.daysInMonth; d++)
        if ((plan.assignments[d]?.nurseIds.length ?? 0) <
                settings.nursesPerDay ||
            (settings.techsPerDay > 0 && plan.assignments[d]?.techId == null))
          d,
    ];
    final monthTitle = DateFormat.yMMMM(
      'tr_TR',
    ).format(DateTime(plan.year, plan.month));

    return Scaffold(
      appBar: AppBar(
        title: Text('$monthTitle Nöbet Listesi'),
        actions: [
          IconButton(
            tooltip: plan.isLocked ? 'Kilidi aç' : 'Kilitle',
            icon: Icon(plan.isLocked ? Icons.lock : Icons.lock_open),
            onPressed: () => controller.setLocked(!plan.isLocked),
          ),
          IconButton(
            tooltip: 'Yeniden oluştur',
            icon: const Icon(Icons.refresh),
            onPressed: () => generateRoster(context, ref),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          if (plan.isLocked)
            ListTile(
              leading: const Icon(Icons.lock),
              title: const Text('Liste kilitli'),
              subtitle: const Text('Yeniden oluşturmak için onay istenir.'),
              tileColor: theme.colorScheme.surfaceContainerHighest,
            ),
          if (plan.generatedAt != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(
                'Oluşturulma: '
                '${DateFormat('d MMMM y HH:mm', 'tr_TR').format(plan.generatedAt!)}',
                style: theme.textTheme.bodySmall,
              ),
            ),
          if (missingDays.isNotEmpty)
            Card(
              margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              color: theme.colorScheme.errorContainer,
              child: ListTile(
                leading: Icon(
                  Icons.warning_amber_rounded,
                  color: theme.colorScheme.onErrorContainer,
                ),
                title: Text(
                  '${missingDays.length} günde eksik nöbetçi var: '
                  '${missingDays.map((d) => formatDayMonth(d, plan.month)).join(', ')}',
                  style: TextStyle(color: theme.colorScheme.onErrorContainer),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: RosterTable(
              plan: plan,
              namesById: {for (final p in people) p.id: p.name},
              weekendDays: RosterGenerator.weekendDays(
                plan.year,
                plan.month,
                holidays,
                settings,
              ),
              holidayDays: {
                for (final h in holidays)
                  if (!h.isHalfDay) h.date.day,
              },
              nursesPerDay: settings.nursesPerDay,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Text('Özet', style: theme.textTheme.titleMedium),
          ),
          SummaryTable(summary: summary),
        ],
      ),
    );
  }
}
