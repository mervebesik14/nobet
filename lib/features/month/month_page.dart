import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../../logic/backup_reminder.dart';
import '../../logic/feasibility_checker.dart';
import '../../logic/next_month_reminder.dart';
import '../../logic/turkish_dates.dart';
import '../../models/models.dart';
import '../../shared/brand.dart';
import '../../shared/person_colors.dart';
import '../../shared/widgets/brand_widgets.dart';
import '../../shared/widgets/section_header.dart';
import '../people/people_controller.dart';
import '../roster/manual_entry_flow.dart';
import '../roster/roster_flow.dart';
import '../roster/roster_page.dart';
import 'month_plan_controller.dart';
import 'month_reminder_notifications.dart';
import 'request_collect_page.dart';
import 'unavailable_days_page.dart';
import '../../shared/app_colors.dart';
import '../../shared/providers.dart';
import '../settings/backup_actions.dart';
import '../settings/shift_reminder_notifications.dart';

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
          const _TodayCard(),
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
          if (active.isNotEmpty && !plan.isLocked)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: _CardButton(
                key: const ValueKey('collect-requests'),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const RequestCollectPage(),
                  ),
                ),
                icon: Icons.forum_outlined,
                label: 'İstekleri topla (WhatsApp)',
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

/// Bugünün ve yarının nöbetçileri; telefonu kullanan kişi ("Sen")
/// nöbetteyse vurgulanır. Hiçbir listede yoksa gösterilmez.
class _TodayCard extends ConsumerWidget {
  const _TodayCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final days = ref.watch(todayOverviewProvider);
    if (!days.any((d) => d.hasRoster)) return const SizedBox.shrink();
    final people = {for (final p in ref.watch(peopleProvider)) p.id: p};
    final self = ref.watch(selfPersonProvider);
    return Padding(
      key: const ValueKey('today-card'),
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        children: [
          _DayHero(day: days[0], people: people, self: self),
          _DayCompact(day: days[1], people: people, self: self),
        ],
      ),
    );
  }
}

/// Günün kişileri: (kişi, vardiya kodu) grupları.
typedef _Who = ({String id, String code, bool extra});

List<(String, List<_Who>)> _groups(DayOverview d) {
  String seatCode(String id) =>
      d.shift16aIds.contains(id) ? '16A' : d.customShifts[id] ?? '24';
  return [
    if (d.nurseIds.isNotEmpty)
      (
        'Hemşire',
        [
          for (final id in d.nurseIds)
            (id: id, code: seatCode(id), extra: false),
        ],
      ),
    if (d.techId != null || d.tech16bId != null)
      (
        'Radyoloji',
        [
          if (d.techId case final id?)
            (id: id, code: seatCode(id), extra: false),
          if (d.tech16bId case final id?) (id: id, code: '16B', extra: false),
        ],
      ),
    if (d.dayShiftIds.isNotEmpty)
      (
        '7A',
        [for (final id in d.dayShiftIds) (id: id, code: '7A', extra: false)],
      ),
    if (d.extraShifts.isNotEmpty)
      (
        'Ek mesai',
        [
          for (final e in d.extraShifts.entries)
            (id: e.key, code: e.value, extra: true),
        ],
      ),
  ];
}

bool _onDuty(DayOverview d, String? self) =>
    self != null &&
    [
      ...d.nurseIds,
      ?d.techId,
      ?d.tech16bId,
      ...d.dayShiftIds,
      ...d.extraShifts.keys,
    ].contains(self);

/// Bugün: marka degradeli büyük kart, kişiler avatarlarıyla.
class _DayHero extends StatelessWidget {
  const _DayHero({required this.day, required this.people, this.self});

  final DayOverview day;
  final Map<String, Person> people;
  final String? self;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brand = context.brand;
    final onDuty = _onDuty(day, self);
    final groups = _groups(day);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(brand.headerStart, Colors.white, 0.06)!,
            brand.headerEnd,
          ],
        ),
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: brand.headerEnd.withValues(alpha: 0.45),
            blurRadius: 22,
            spreadRadius: -8,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  'BUGÜN',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  formatDayMonthWeekday(
                    day.date.year,
                    day.date.month,
                    day.date.day,
                  ),
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (onDuty) const _OnDutyBadge(),
            ],
          ),
          const SizedBox(height: 14),
          if (!day.hasRoster)
            Text(
              'Bu ayın listesi yok.',
              style: TextStyle(color: brand.onHeaderMuted),
            )
          else if (groups.isEmpty)
            Text(
              'Nöbetçi yazılmamış.',
              style: TextStyle(color: brand.onHeaderMuted),
            )
          else
            Wrap(
              spacing: 18,
              runSpacing: 14,
              children: [
                for (final (label, who) in groups)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label.toUpperCase(),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: brand.onHeaderMuted,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (final w in who)
                            Padding(
                              padding: const EdgeInsets.only(right: 12),
                              child: _PersonChip(
                                person: people[w.id],
                                id: w.id,
                                code: w.code,
                                extra: w.extra,
                                highlight: w.id == self,
                                onDark: true,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
              ],
            ),
          if (day.backupIds.isNotEmpty) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.support_outlined,
                    size: 16,
                    color: brand.onHeaderMuted,
                  ),
                  const SizedBox(width: 6),
                  Text('Yedek: ', style: TextStyle(color: brand.onHeaderMuted)),
                  for (final id in day.backupIds) ...[
                    _MiniAvatar(person: people[id], id: id),
                    const SizedBox(width: 4),
                    Text(
                      _first(people[id]?.name ?? 'Silinmiş kişi'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Yarın: sade kart, küçük avatarlar.
class _DayCompact extends StatelessWidget {
  const _DayCompact({required this.day, required this.people, this.self});

  final DayOverview day;
  final Map<String, Person> people;
  final String? self;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brand = context.brand;
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final groups = _groups(day);
    return GroupCard(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'YARIN',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: brand.onPill,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      formatDayMonthWeekday(
                        day.date.year,
                        day.date.month,
                        day.date.day,
                      ),
                      style: muted,
                    ),
                  ),
                  if (_onDuty(day, self)) const _OnDutyBadge(light: true),
                ],
              ),
              const SizedBox(height: 10),
              if (!day.hasRoster)
                Text('Bu ayın listesi yok.', style: muted)
              else if (groups.isEmpty)
                Text('Nöbetçi yazılmamış.', style: muted)
              else
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    for (final (_, who) in groups)
                      for (final w in who)
                        _PersonChip(
                          person: people[w.id],
                          id: w.id,
                          code: w.code,
                          extra: w.extra,
                          highlight: w.id == self,
                          compact: true,
                        ),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }
}

String _first(String name) => name.trim().split(RegExp(r'\s+')).first;

/// Avatar + ad + vardiya etiketi.
class _PersonChip extends StatelessWidget {
  const _PersonChip({
    required this.person,
    required this.id,
    required this.code,
    this.extra = false,
    this.highlight = false,
    this.onDark = false,
    this.compact = false,
  });

  final Person? person;
  final String id;
  final String code;

  /// Koltuk doldurmayan ek mesai mi (renk için)?
  final bool extra;
  final bool highlight;
  final bool onDark;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final name = person?.name ?? 'Silinmiş kişi';
    final color = person == null
        ? PersonColors.forId(id)
        : PersonColors.of(person!);
    final tag = Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: scheme.shiftColor(code, extra: extra),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        code,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
    final avatar = Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          width: 2,
          color: highlight
              ? const Color(0xFFFFD54F)
              : onDark
              ? Colors.white.withValues(alpha: 0.5)
              : Colors.transparent,
        ),
      ),
      child: PersonAvatar(name: name, color: color, radius: compact ? 14 : 22),
    );
    final nameText = Text(
      _first(name),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: (compact ? theme.textTheme.bodySmall : theme.textTheme.bodyMedium)
          ?.copyWith(
            color: onDark ? Colors.white : null,
            fontWeight: FontWeight.w600,
          ),
    );
    if (compact) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          avatar,
          const SizedBox(width: 6),
          nameText,
          const SizedBox(width: 4),
          tag,
        ],
      );
    }
    return SizedBox(
      width: 64,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              avatar,
              Positioned(right: -6, bottom: -4, child: tag),
            ],
          ),
          const SizedBox(height: 6),
          nameText,
        ],
      ),
    );
  }
}

class _MiniAvatar extends StatelessWidget {
  const _MiniAvatar({required this.person, required this.id});

  final Person? person;
  final String id;

  @override
  Widget build(BuildContext context) => PersonAvatar(
    name: person?.name ?? '?',
    color: person == null ? PersonColors.forId(id) : PersonColors.of(person!),
    radius: 10,
  );
}

/// "Nöbettesin" rozeti: parlak, gölgeli.
class _OnDutyBadge extends StatelessWidget {
  const _OnDutyBadge({this.light = false});

  final bool light;

  @override
  Widget build(BuildContext context) {
    const gold = Color(0xFFFFC94D);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFFFFE08A), gold]),
        borderRadius: BorderRadius.circular(99),
        boxShadow: [
          BoxShadow(
            color: gold.withValues(alpha: light ? 0.35 : 0.6),
            blurRadius: 12,
            spreadRadius: 1,
          ),
        ],
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.local_hospital, size: 13, color: Color(0xFF5A3D00)),
          SizedBox(width: 4),
          Text(
            'Nöbettesin',
            style: TextStyle(
              color: Color(0xFF5A3D00),
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

/// Beyaz kart görünümlü düğme ("Listeyi elle gir").
class _CardButton extends StatelessWidget {
  const _CardButton({
    super.key,
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
