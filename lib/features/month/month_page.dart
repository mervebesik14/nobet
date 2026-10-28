import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../../logic/backup_reminder.dart';
import '../../logic/feasibility_checker.dart';
import '../../logic/next_month_reminder.dart';
import '../../logic/turkish_dates.dart';
import '../../models/models.dart';
import '../../shared/brand.dart';
import '../../shared/widgets/brand_widgets.dart';
import '../../shared/widgets/section_header.dart';
import '../people/people_controller.dart';
import '../roster/manual_entry_flow.dart';
import '../roster/roster_flow.dart';
import '../roster/roster_page.dart';
import 'month_plan_controller.dart';
import 'month_reminder_notifications.dart';
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
      appBar: BrandHeader(
        title: 'Ay Planı',
        bottom: HeaderMonthSelector(
          month: month,
          onChanged: ref.read(planMonthProvider.notifier).select,
        ),
      ),
      floatingActionButton: active.isEmpty
          ? null
          : plan.hasRoster
          ? FloatingActionButton.extended(
              // Sekmeler birlikte durduğu için kahraman geçişi yok.
              heroTag: null,
              onPressed: () => _openRoster(context),
              icon: const Icon(Icons.table_chart_outlined),
              label: const Text('Listeyi Gör'),
            )
          : FloatingActionButton.extended(
              // Sekmeler birlikte durduğu için kahraman geçişi yok.
              heroTag: null,
              onPressed: () => _create(context, ref),
              icon: const Icon(Icons.auto_awesome),
              label: const Text('Listeyi Oluştur'),
            ),
      body: ListView(
        // FAB son kartı örtmesin.
        padding: const EdgeInsets.only(top: 8, bottom: 96),
        children: [
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
            acknowledged: ref
                .watch(monthReminderStartedProvider)
                .contains(MonthReminderStarted.keyOf(next.year, next.month)),
            viewingNextMonth:
                month.year == next.year && month.month == next.month,
            snoozedUntil: ref.watch(nextMonthReminderSnoozeProvider),
            day: ref.watch(monthReminderDayProvider),
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
              child: Row(
                children: [
                  Expanded(
                    child: _CardButton(
                      onPressed: () async {
                        // Elle girilen liste dokunarak düzenlenmeye hazır açılır.
                        if (await manualEntryFlow(context, ref) &&
                            context.mounted) {
                          _openRoster(context, freeEdit: true);
                        }
                      },
                      icon: Icons.edit_note,
                      label: 'Listeyi elle gir',
                    ),
                  ),
                  if (plan.hasRoster) ...[
                    const SizedBox(width: 10),
                    Expanded(
                      child: _CardButton(
                        onPressed: () => resetRosterFlow(context, ref),
                        icon: Icons.delete_outline,
                        label: 'Listeyi sıfırla',
                      ),
                    ),
                  ],
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
              GroupCard(
                children: [
                  for (final person in active.where((p) => p.role == role))
                    _PersonRow(
                      person: person,
                      unavailableCount: plan
                          .unavailableDaysOf(person.id)
                          .length,
                      annualLeaveCount: plan.annualLeaveOf(person.id).length,
                      radiationLeaveCount: plan
                          .radiationLeaveOf(person.id)
                          .length,
                      sickLeaveCount: plan.sickLeaveOf(person.id).length,
                      wantsOvertime: plan.wantsOvertime(person.id),
                      requestedCount: plan.requestedShiftsOf(person.id).length,
                    ),
                ],
              ),
            ],
          _FeasibilitySection(report: report),
        ],
      ),
    );
  }
}

/// Beyaz kart görünümlü düğme ("Listeyi elle gir").
class _CardButton extends StatelessWidget {
  const _CardButton({
    required this.onPressed,
    required this.icon,
    required this.label,
  });

  final VoidCallback onPressed;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 20),
      label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      style: OutlinedButton.styleFrom(
        backgroundColor: context.brand.card,
        foregroundColor: theme.colorScheme.onSurface,
        side: BorderSide(color: context.brand.divider),
        minimumSize: const Size.fromHeight(48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: theme.textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w700,
        ),
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
          if (unavailableCount == 0)
            Text(
              'İstenmeyen gün yok',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.outline,
              ),
            )
          else
            _StatusLine(
              icon: Icons.cancel_outlined,
              text: '$unavailableCount gün istemiyor',
              color: theme.colorScheme.error,
            ),
          if (requestedCount > 0)
            _StatusLine(
              icon: Icons.check,
              text: '$requestedCount gün nöbet seçildi',
              color: theme.colorScheme.primary,
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
            _StatusLine(
              icon: Icons.more_time,
              text: 'Fazla mesai istiyor',
              color: theme.colorScheme.primary,
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

/// Kişi satırında simgeli, renkli kısa durum ("6 gün istemiyor").
class _StatusLine extends StatelessWidget {
  const _StatusLine({
    required this.icon,
    required this.text,
    required this.color,
  });

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 2),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 4),
        Text(
          text,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: color,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
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
/// toplamaya başlatır. "Sonra" birkaç gün susturur, "Başladım" o ay için
/// kartı ve tekrarlayan bildirimleri kapatır.
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
            // Dar ekranda düğmeler alt satıra kayar.
            Wrap(
              alignment: WrapAlignment.end,
              children: [
                TextButton(
                  onPressed: () => ref
                      .read(nextMonthReminderSnoozeProvider.notifier)
                      .snooze(
                        ref.read(todayProvider).add(NextMonthReminder.snooze),
                      ),
                  child: const Text('Sonra'),
                ),
                TextButton(
                  onPressed: () {
                    ref
                        .read(monthReminderStartedProvider.notifier)
                        .markStarted(month.year, month.month);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          '$name hatırlatması kapandı. Kolay gelsin!',
                        ),
                      ),
                    );
                  },
                  child: const Text('Başladım'),
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
