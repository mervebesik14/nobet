import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../../logic/backup_reminder.dart';
import '../../logic/feasibility_checker.dart';
import '../../logic/next_month_reminder.dart';
import '../../logic/turkish_dates.dart';
import '../../models/models.dart';
import '../../shared/widgets/month_selector.dart';
import '../../shared/widgets/section_header.dart';
import '../people/people_controller.dart';
import '../roster/manual_entry_flow.dart';
import '../roster/roster_flow.dart';
import '../roster/roster_page.dart';
import 'month_plan_controller.dart';
import 'unavailable_days_page.dart';
import '../../shared/app_colors.dart';
import '../../shared/providers.dart';
import '../settings/backup_actions.dart';

/// Ay Planı sekmesi: ay seçici, aktif kişiler ve istenmeyen gün sayıları,
/// liste oluşturmadan önceki uygunluk uyarıları.
class MonthPage extends ConsumerWidget {
  const MonthPage({super.key});

  static void _openRoster(BuildContext context, {bool freeEdit = false}) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => RosterPage(freeEdit: freeEdit)),
      );

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    if (await generateRoster(context, ref) && context.mounted) {
      _openRoster(context);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = ref.watch(planMonthProvider);
    final plan = ref.watch(monthPlanProvider);
    // Bu ay en az bir gün aktif olanlar (ay içinde pasife geçen de dahil).
    final active = ref
        .watch(peopleProvider)
        .where((p) => p.worksInMonth(plan.year, plan.month))
        .toList();
    final report = ref.watch(monthFeasibilityProvider);
    final theme = Theme.of(context);
    final backup = ref.watch(backupStatusProvider);
    final today = ref.watch(todayProvider);
    final next = NextMonthReminder.nextMonth(today);
    final nextPlan = ref
        .watch(monthPlanRepositoryProvider)
        .get(next.year, next.month);

    return Scaffold(
      appBar: AppBar(title: const Text('Ay Planı')),
      floatingActionButton: active.isEmpty
          ? null
          : plan.hasRoster
          ? FloatingActionButton.extended(
              onPressed: () => _openRoster(context),
              icon: const Icon(Icons.table_chart_outlined),
              label: const Text('Listeyi Gör'),
            )
          : FloatingActionButton.extended(
              onPressed: () => _create(context, ref),
              icon: const Icon(Icons.auto_awesome),
              label: const Text('Listeyi Oluştur'),
            ),
      body: ListView(
        // FAB son kartı örtmesin.
        padding: const EdgeInsets.only(bottom: 96),
        children: [
          MonthSelector(
            month: month,
            onChanged: ref.read(planMonthProvider.notifier).select,
          ),
          if (BackupReminder.isDue(
            today: ref.watch(todayProvider),
            hasData: ref.watch(peopleProvider).isNotEmpty,
            lastBackup: backup.lastBackup,
            snoozedUntil: backup.snoozedUntil,
          ))
            _BackupReminderCard(lastBackup: backup.lastBackup),
          if (NextMonthReminder.isDue(
            today: today,
            hasPeople: ref.watch(peopleProvider).any((p) => p.isActive),
            nextMonthHasRoster: nextPlan?.hasRoster ?? false,
            viewingNextMonth:
                month.year == next.year && month.month == next.month,
            snoozedUntil: ref.watch(nextMonthReminderSnoozeProvider),
          ))
            _NextMonthReminderCard(month: next, plan: nextPlan),
          if (plan.isLocked)
            Card(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: ListTile(
                leading: const Icon(Icons.lock_outline),
                title: Text(
                  ref.read(monthPlanProvider.notifier).isPastMonth(plan)
                      ? 'Geçmiş ay: liste salt okunur.'
                      : 'Bu ay kilitli.',
                ),
                subtitle: const Text(
                  'İstenmeyen günler ve liste değiştirilemez.',
                ),
                trailing: TextButton(
                  onPressed: () =>
                      ref.read(monthPlanProvider.notifier).setLocked(false),
                  child: const Text('Kilidi aç'),
                ),
                tileColor: theme.colorScheme.headerTint,
              ),
            ),
          if (active.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  OutlinedButton.icon(
                    onPressed: () async {
                      // Elle girilen liste dokunarak düzenlenmeye hazır açılır.
                      if (await manualEntryFlow(context, ref) &&
                          context.mounted) {
                        _openRoster(context, freeEdit: true);
                      }
                    },
                    icon: const Icon(Icons.edit_note),
                    label: const Text('Listeyi elle gir'),
                  ),
                  if (plan.hasRoster)
                    OutlinedButton.icon(
                      onPressed: () => resetRosterFlow(context, ref),
                      icon: const Icon(Icons.delete_sweep_outlined),
                      label: const Text('Listeyi sıfırla'),
                    ),
                ],
              ),
            ),
          if (active.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Aktif kişi yok. Önce Kişiler sekmesinden hemşire ve '
                'teknikerleri ekleyin.',
                textAlign: TextAlign.center,
              ),
            ),
          for (final role in Role.values)
            if (active.any((p) => p.role == role)) ...[
              SectionHeader(
                title: role.pluralLabel,
                count: active.where((p) => p.role == role).length,
              ),
              for (final person in active.where((p) => p.role == role))
                _PersonRow(
                  person: person,
                  unavailableCount: plan.unavailableDaysOf(person.id).length,
                  annualLeaveCount: plan.annualLeaveOf(person.id).length,
                  radiationLeaveCount: plan.radiationLeaveOf(person.id).length,
                  sickLeaveCount: plan.sickLeaveOf(person.id).length,
                  wantsOvertime: plan.wantsOvertime(person.id),
                  requestedCount: plan.requestedShiftsOf(person.id).length,
                ),
            ],
          _FeasibilitySection(report: report),
        ],
      ),
    );
  }
}

class _PersonRow extends StatelessWidget {
  const _PersonRow({
    required this.person,
    required this.unavailableCount,
    required this.annualLeaveCount,
    required this.radiationLeaveCount,
    this.sickLeaveCount = 0,
    required this.wantsOvertime,
    this.requestedCount = 0,
  });

  final Person person;
  final int unavailableCount;
  final int annualLeaveCount;
  final int radiationLeaveCount;
  final int sickLeaveCount;
  final bool wantsOvertime;
  final int requestedCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      title: Text(person.name),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            unavailableCount == 0
                ? 'İstenmeyen gün yok'
                : '$unavailableCount gün istemiyor',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: unavailableCount == 0
                  ? theme.colorScheme.outline
                  : theme.colorScheme.error,
            ),
          ),
          if (requestedCount > 0)
            Text(
              '$requestedCount gün nöbet seçildi',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          if (annualLeaveCount > 0)
            _LeaveLine(
              icon: Icons.beach_access_outlined,
              text: '$annualLeaveCount gün yıllık izin',
            ),
          if (radiationLeaveCount > 0)
            _LeaveLine(
              icon: Icons.radio_button_checked,
              text: '$radiationLeaveCount gün şua izni',
            ),
          if (sickLeaveCount > 0)
            _LeaveLine(
              icon: Icons.medical_services_outlined,
              text: '$sickLeaveCount gün rapor',
            ),
          if (wantsOvertime)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.more_time,
                  size: 16,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 4),
                Text(
                  'Fazla mesai istiyor',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
        ],
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => UnavailableDaysPage(person: person),
        ),
      ),
    );
  }
}

class _LeaveLine extends StatelessWidget {
  const _LeaveLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.leaveColor;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 4),
        Text(
          text,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color),
        ),
      ],
    );
  }
}

class _FeasibilitySection extends StatelessWidget {
  const _FeasibilitySection({required this.report});

  final FeasibilityReport report;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 24, 16, 0),
      color: report.isFeasible
          ? theme.colorScheme.headerTint
          : theme.colorScheme.dangerTint,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              leading: Icon(
                report.isFeasible
                    ? Icons.check_circle_outline
                    : Icons.warning_amber_rounded,
                color: report.isFeasible
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onErrorContainer,
              ),
              title: Text(
                report.isFeasible
                    ? 'Uygunluk kontrolü: sorun görünmüyor'
                    : 'Uygunluk kontrolü: ${report.issues.length} sorun',
                style: TextStyle(
                  color: report.isFeasible
                      ? null
                      : theme.colorScheme.onErrorContainer,
                ),
              ),
            ),
            for (final issue in report.issues)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  '• ${issue.message}',
                  style: TextStyle(color: theme.colorScheme.onErrorContainer),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Düzenli yedek hatırlatması: "Yedek al" paylaşır, "Sonra" bir hafta susturur.
class _BackupReminderCard extends ConsumerWidget {
  const _BackupReminderCard({required this.lastBackup});

  final DateTime? lastBackup;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final days = BackupReminder.daysSince(ref.watch(todayProvider), lastBackup);
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      color: theme.colorScheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.backup_outlined,
                  color: theme.colorScheme.onTertiaryContainer,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    days == null
                        ? 'Henüz yedek alınmadı. Veriler yalnızca bu '
                              'telefonda; kaybolmasın diye yedek alın.'
                        : '$days gündür yedek alınmadı.',
                    style: TextStyle(
                      color: theme.colorScheme.onTertiaryContainer,
                    ),
                  ),
                ),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () {
                    final today = ref.read(todayProvider);
                    ref
                        .read(backupStatusProvider.notifier)
                        .snooze(today.add(BackupReminder.snooze));
                  },
                  child: const Text('Sonra'),
                ),
                FilledButton.tonal(
                  onPressed: () => exportBackup(context, ref),
                  child: const Text('Yedek al'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Ay başı hatırlatması: gelecek ayın listesi henüz yoksa istekleri
/// toplamaya başlatır. "Sonra" birkaç gün susturur.
class _NextMonthReminderCard extends ConsumerWidget {
  const _NextMonthReminderCard({required this.month, required this.plan});

  final DateTime month;
  final MonthPlan? plan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final name = turkishMonthNames[month.month - 1];
    final entered =
        plan?.blockedDays.values.where((d) => d.isNotEmpty).length ?? 0;
    final color = theme.colorScheme.onSecondaryContainer;
    return Card(
      key: const ValueKey('next-month-reminder'),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      color: theme.colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.event_note_outlined, color: color),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '$name listesi henüz oluşturulmadı. İstenmeyen günleri '
                    've izinleri toplamaya başla.'
                    '${entered > 0 ? '\nŞu ana kadar $entered kişinin '
                              'girişi var.' : ''}',
                    style: TextStyle(color: color),
                  ),
                ),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => ref
                      .read(nextMonthReminderSnoozeProvider.notifier)
                      .snooze(
                        ref.read(todayProvider).add(NextMonthReminder.snooze),
                      ),
                  child: const Text('Sonra'),
                ),
                FilledButton.tonal(
                  onPressed: () =>
                      ref.read(planMonthProvider.notifier).select(month),
                  child: Text('$name ayına geç'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
