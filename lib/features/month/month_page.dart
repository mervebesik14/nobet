import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../logic/feasibility_checker.dart';
import '../../models/models.dart';
import '../../shared/widgets/month_selector.dart';
import '../../shared/widgets/section_header.dart';
import '../people/people_controller.dart';
import '../roster/roster_flow.dart';
import '../roster/roster_page.dart';
import '../roster/yearly_summary_page.dart';
import 'month_plan_controller.dart';
import 'unavailable_days_page.dart';
import '../../shared/app_colors.dart';

/// Ay Planı sekmesi: ay seçici, aktif kişiler ve istenmeyen gün sayıları,
/// liste oluşturmadan önceki uygunluk uyarıları.
class MonthPage extends ConsumerWidget {
  const MonthPage({super.key});

  static void _openRoster(BuildContext context) => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => const RosterPage()));

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    if (await generateRoster(context, ref) && context.mounted) {
      _openRoster(context);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = ref.watch(planMonthProvider);
    final plan = ref.watch(monthPlanProvider);
    final active = ref.watch(peopleProvider).where((p) => p.isActive).toList();
    final report = ref.watch(monthFeasibilityProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ay Planı'),
        actions: [
          IconButton(
            tooltip: 'Yıllık Özet',
            icon: const Icon(Icons.insights),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => YearlySummaryPage(initialYear: month.year),
              ),
            ),
          ),
        ],
      ),
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
                  leaveCount: plan.annualLeaveOf(person.id).length,
                  wantsOvertime: plan.wantsOvertime(person.id),
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
    required this.leaveCount,
    required this.wantsOvertime,
  });

  final Person person;
  final int unavailableCount;
  final int leaveCount;
  final bool wantsOvertime;

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
          if (leaveCount > 0)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.beach_access_outlined,
                  size: 16,
                  color: theme.colorScheme.leaveColor,
                ),
                const SizedBox(width: 4),
                Text(
                  '$leaveCount gün yıllık izin',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.leaveColor,
                  ),
                ),
              ],
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
