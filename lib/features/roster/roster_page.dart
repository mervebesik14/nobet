import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../data/providers.dart';
import '../../logic/roster_editor.dart';
import '../../logic/roster_generator.dart';
import '../../logic/roster_summary.dart';
import '../../logic/roster_validator.dart';
import '../../logic/turkish_collation.dart';
import '../../logic/turkish_dates.dart';
import '../../models/models.dart';
import '../holidays/holidays_controller.dart';
import '../month/month_plan_controller.dart';
import '../people/people_controller.dart';
import '../../shared/platform_services.dart';
import 'edit_sheet.dart';
import 'roster_pdf.dart';
import 'roster_flow.dart';
import 'roster_table.dart';
import 'summary_table.dart';

/// Seçili ayın nöbet listesi, elle düzenleme, kural uyarıları ve özet.
///
/// Hücreye dokun: o gün için seçenekler (kaldır / başkasıyla değiştir /
/// bu kişiyi ata). Nöbete uzun bas: takas modu; ikinci nöbete dokununca iki
/// nöbet yer değiştirir. Her değişiklikten sonra kurallar yeniden denetlenir.
class RosterPage extends ConsumerStatefulWidget {
  const RosterPage({super.key});

  @override
  ConsumerState<RosterPage> createState() => _RosterPageState();
}

class _RosterPageState extends ConsumerState<RosterPage> {
  /// Takas modunda seçilen ilk nöbet.
  RosterCell? _swapFrom;

  MonthPlan get _plan => ref.read(monthPlanProvider);

  void _notify(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Map<String, Person> get _peopleById => {
    for (final p in ref.read(peopleProvider)) p.id: p,
  };

  String _name(String id) => _peopleById[id]?.name ?? 'Silinmiş kişi';

  String _dayLabel(int day) => DateFormat(
    'd MMMM EEEE',
    'tr_TR',
  ).format(DateTime(_plan.year, _plan.month, day));

  List<RuleViolation> _validate(Map<int, DayAssignment> assignments) {
    final plan = _plan;
    return RosterValidator(ref.read(rosterSettingsProvider)).validate(
      year: plan.year,
      month: plan.month,
      assignments: assignments,
      people: ref.read(peopleProvider),
      unavailableDays: plan.unavailableDays,
      previousMonthTail: ref
          .read(monthPlanProvider.notifier)
          .previousMonthTail(),
    );
  }

  /// [after] uygulanırsa [personId] için yeni çıkan ihlaller.
  List<String> _newWarnings(
    String personId,
    Map<int, DayAssignment> after,
    Set<String> before,
  ) => [
    for (final v in _validate(after))
      if (v.personId == personId &&
          v.kind != ViolationKind.missing &&
          !before.contains(v.message))
        v.message,
  ];

  Set<String> _currentMessages() => {
    for (final v in ref.read(rosterViolationsProvider)) v.message,
  };

  bool _ensureUnlocked() {
    if (!_plan.isLocked) return true;
    _notify('Liste kilitli; düzenlemek için kilidi açın.');
    return false;
  }

  Future<void> _apply(Map<int, DayAssignment>? result) async {
    if (result == null) return;
    await ref.read(monthPlanProvider.notifier).setAssignments(result);
  }

  /// Aynı roldeki aktif kişiler, Türkçe ada göre.
  List<Person> _activeOfRole(Role role) =>
      ref
          .read(peopleProvider)
          .where((p) => p.isActive && p.role == role)
          .toList()
        ..sort((a, b) => compareTurkish(a.name, b.name));

  Future<void> _onCellTap(RosterCell cell, Role role) async {
    if (_swapFrom != null) return _completeSwap(cell, role);
    if (!_ensureUnlocked()) return;

    final plan = _plan;
    final nursesPerDay = ref.read(rosterSettingsProvider).nursesPerDay;
    final day = cell.day;
    final id = cell.personId;
    final current = plan.assignments[day] ?? DayAssignment(day: day);
    final before = _currentMessages();
    final roleIds = role == Role.nurse ? current.nurseIds : [?current.techId];

    Map<int, DayAssignment> replace(String? oldId, String? newId) =>
        RosterEditor.replace(
          plan.assignments,
          day: day,
          role: role,
          oldId: oldId,
          newId: newId,
          nursesPerDay: nursesPerDay,
        );

    final Map<int, DayAssignment>? result;
    if (current.includes(id)) {
      result = await showEditSheet(
        context,
        title: '${_name(id)} · ${_dayLabel(day)}',
        actions: [
          EditOption(
            title: 'Nöbeti kaldır',
            subtitle: 'Koltuk boş kalır.',
            icon: Icons.remove_circle_outline,
            result: replace(id, null),
          ),
        ],
        candidatesTitle: 'Yerine atanabilecekler',
        candidates: [
          for (final p in _activeOfRole(role))
            if (!current.includes(p.id))
              () {
                final after = replace(id, p.id);
                return EditOption(
                  title: p.name,
                  result: after,
                  warnings: _newWarnings(p.id, after, before),
                );
              }(),
        ],
      );
    } else {
      final perDay = role == Role.nurse ? nursesPerDay : 1;
      result = await showEditSheet(
        context,
        title: '${_name(id)} · ${_dayLabel(day)}',
        subtitle: 'Bu güne ata',
        candidates: [
          if (roleIds.length < perDay)
            () {
              final after = replace(null, id);
              return EditOption(
                title: 'Boş koltuğa ata',
                result: after,
                warnings: _newWarnings(id, after, before),
              );
            }(),
          for (final other in roleIds)
            () {
              final after = replace(other, id);
              return EditOption(
                title: '${_name(other)} yerine ata',
                result: after,
                warnings: _newWarnings(id, after, before),
              );
            }(),
        ],
      );
    }
    await _apply(result);
  }

  Future<void> _onMissingTap(int day) async {
    if (_swapFrom != null) {
      _notify('Takas için başka bir nöbete (24) dokunun.');
      return;
    }
    if (!_ensureUnlocked()) return;
    final plan = _plan;
    final settings = ref.read(rosterSettingsProvider);
    final current = plan.assignments[day] ?? DayAssignment(day: day);
    final before = _currentMessages();

    final candidates = <EditOption>[];
    for (final role in Role.values) {
      final empty = role == Role.nurse
          ? current.nurseIds.length < settings.nursesPerDay
          : settings.techsPerDay > 0 && current.techId == null;
      if (!empty) continue;
      for (final p in _activeOfRole(role)) {
        if (current.includes(p.id)) continue;
        final after = RosterEditor.replace(
          plan.assignments,
          day: day,
          role: role,
          newId: p.id,
          nursesPerDay: settings.nursesPerDay,
        );
        candidates.add(
          EditOption(
            title: '${p.name} (${role.label})',
            result: after,
            warnings: _newWarnings(p.id, after, before),
          ),
        );
      }
    }
    final result = await showEditSheet(
      context,
      title: '${_dayLabel(day)} · boş koltuk',
      candidatesTitle: 'Atanabilecekler',
      candidates: candidates,
    );
    await _apply(result);
  }

  void _onCellLongPress(RosterCell cell) {
    if (!_ensureUnlocked()) return;
    if (!(_plan.assignments[cell.day]?.includes(cell.personId) ?? false)) {
      _notify('Takas için nöbet olan bir hücreye (24) uzun basın.');
      return;
    }
    setState(() => _swapFrom = cell);
  }

  Future<void> _completeSwap(RosterCell cell, Role role) async {
    final from = _swapFrom!;
    if (from == cell) {
      setState(() => _swapFrom = null);
      return;
    }
    final plan = _plan;
    if (!(plan.assignments[cell.day]?.includes(cell.personId) ?? false)) {
      _notify('Takas için başka bir nöbete (24) dokunun.');
      return;
    }
    final fromRole = _roleOf(from.personId, from.day);
    if (fromRole != role) {
      _notify('Takas yalnızca aynı görevdeki kişiler arasında yapılır.');
      return;
    }
    try {
      final result = RosterEditor.swap(
        plan.assignments,
        a: from.personId,
        dayA: from.day,
        b: cell.personId,
        dayB: cell.day,
        role: role,
        nursesPerDay: ref.read(rosterSettingsProvider).nursesPerDay,
      );
      setState(() => _swapFrom = null);
      await _apply(result);
      _notify(
        '${_name(from.personId)} ${formatDayMonth(from.day, plan.month)} ↔ '
        '${_name(cell.personId)} ${formatDayMonth(cell.day, plan.month)} '
        'takas edildi.',
      );
    } on RosterEditException catch (e) {
      _notify('Takas yapılamaz: ${e.message}');
    }
  }

  /// Listeyi PDF / PNG olarak paylaşır ya da yazdırır.
  Future<void> _share(
    _ShareAction action, {
    required MonthPlan plan,
    required List<RosterRow> rows,
    required RosterSummary summary,
    required Set<int> weekendDays,
    required Set<int> holidayDays,
    required Map<int, int> missingByDay,
    required int shiftHours,
  }) async {
    final services = ref.read(platformServicesProvider);
    final fileBase =
        'nobet-listesi-${plan.year}-${plan.month.toString().padLeft(2, '0')}';
    final title =
        '${DateFormat.yMMMM('tr_TR').format(DateTime(plan.year, plan.month))} '
        'Nöbet Listesi';
    try {
      final fonts = await services.loadPdfFonts();
      final pdf = await buildRosterPdf(
        plan: plan,
        rows: rows,
        summary: summary,
        weekendDays: weekendDays,
        holidayDays: holidayDays,
        shiftHours: shiftHours,
        missingByDay: missingByDay,
        font: fonts.regular,
        boldFont: fonts.bold,
        singlePage: action == _ShareAction.png,
      );
      switch (action) {
        case _ShareAction.pdf:
          await services.sharePdf(pdf, '$fileBase.pdf');
        case _ShareAction.png:
          final png = await services.pdfToPng(pdf);
          await services.shareFile(png, '$fileBase.png', 'image/png');
        case _ShareAction.print:
          await services.printPdf(pdf, title);
      }
    } catch (e) {
      if (mounted) _notify('Paylaşılamadı: $e');
    }
  }

  /// Kişinin o gün oturduğu koltuğun rolü.
  Role? _roleOf(String id, int day) {
    final a = _plan.assignments[day];
    if (a == null) return null;
    if (a.nurseIds.contains(id)) return Role.nurse;
    if (a.techId == id) return Role.radiologyTech;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final plan = ref.watch(monthPlanProvider);
    final people = ref.watch(peopleProvider);
    final settings = ref.watch(rosterSettingsProvider);
    final violations = ref.watch(rosterViolationsProvider);
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
    final missingByDay = <int, int>{};
    for (var d = 1; d <= plan.daysInMonth; d++) {
      final a = plan.assignments[d];
      final missing =
          max(0, settings.nursesPerDay - (a?.nurseIds.length ?? 0)) +
          (settings.techsPerDay > 0 && a?.techId == null ? 1 : 0);
      if (missing > 0) missingByDay[d] = missing;
    }
    final rows = [
      for (final r in summary.people)
        (id: r.personId, name: r.name, role: r.role),
    ];
    final roleById = {for (final r in rows) r.id: r.role};
    final weekendDays = RosterGenerator.weekendDays(
      plan.year,
      plan.month,
      holidays,
      settings,
    );
    final holidayDays = {
      for (final h in holidays)
        if (!h.isHalfDay) h.date.day,
    };
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
            onPressed: () {
              setState(() => _swapFrom = null);
              controller.setLocked(!plan.isLocked);
            },
          ),
          IconButton(
            tooltip: 'Yeniden oluştur',
            icon: const Icon(Icons.refresh),
            onPressed: () {
              setState(() => _swapFrom = null);
              generateRoster(context, ref);
            },
          ),
          PopupMenuButton<_ShareAction>(
            tooltip: 'Paylaş',
            icon: const Icon(Icons.share),
            onSelected: (action) => _share(
              action,
              plan: plan,
              rows: rows,
              summary: summary,
              weekendDays: weekendDays,
              holidayDays: holidayDays,
              missingByDay: missingByDay,
              shiftHours: settings.shiftHours,
            ),
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: _ShareAction.pdf,
                child: ListTile(
                  leading: Icon(Icons.picture_as_pdf_outlined),
                  title: Text('PDF olarak paylaş'),
                ),
              ),
              PopupMenuItem(
                value: _ShareAction.png,
                child: ListTile(
                  leading: Icon(Icons.image_outlined),
                  title: Text('Görsel (PNG) olarak paylaş'),
                ),
              ),
              PopupMenuItem(
                value: _ShareAction.print,
                child: ListTile(
                  leading: Icon(Icons.print_outlined),
                  title: Text('Yazdır'),
                ),
              ),
            ],
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
              subtitle: const Text(
                'Düzenleme kapalı; yeniden oluşturmak onay ister.',
              ),
              tileColor: theme.colorScheme.surfaceContainerHighest,
            )
          else if (_swapFrom case final from?)
            MaterialBanner(
              leading: const Icon(Icons.swap_horiz),
              content: Text(
                'Takas: ${_name(from.personId)} – '
                '${formatDayMonth(from.day, plan.month)} seçildi. '
                'Takas edilecek ikinci nöbete dokunun.',
              ),
              actions: [
                TextButton(
                  onPressed: () => setState(() => _swapFrom = null),
                  child: const Text('İptal'),
                ),
              ],
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Text(
                'Düzenlemek için hücreye dokunun; takas için nöbete uzun '
                'basın.',
                style: theme.textTheme.bodySmall,
              ),
            ),
          if (plan.generatedAt != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text(
                'Oluşturulma: '
                '${DateFormat('d MMMM y HH:mm', 'tr_TR').format(plan.generatedAt!)}',
                style: theme.textTheme.bodySmall,
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: RosterTable(
              plan: plan,
              rows: rows,
              weekendDays: weekendDays,
              holidayDays: holidayDays,
              shiftHours: settings.shiftHours,
              missingByDay: missingByDay,
              violationCells: {
                for (final v in violations)
                  if (v.personId case final id?)
                    for (final d in v.days) (personId: id, day: d),
              },
              selectedCell: _swapFrom,
              onCellTap: (cell) => _onCellTap(cell, roleById[cell.personId]!),
              onCellLongPress: _onCellLongPress,
              onMissingTap: _onMissingTap,
            ),
          ),
          _ViolationList(violations: violations),
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

class _ViolationList extends StatelessWidget {
  const _ViolationList({required this.violations});

  final List<RuleViolation> violations;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (violations.isEmpty) {
      return ListTile(
        leading: Icon(
          Icons.check_circle_outline,
          color: theme.colorScheme.primary,
        ),
        title: const Text('Kural ihlali yok'),
      );
    }
    final onColor = theme.colorScheme.onErrorContainer;
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      color: theme.colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              leading: Icon(Icons.warning_amber_rounded, color: onColor),
              title: Text(
                'Kural ihlalleri (${violations.length})',
                style: TextStyle(color: onColor),
              ),
            ),
            for (final v in violations)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text('• ${v.message}', style: TextStyle(color: onColor)),
              ),
          ],
        ),
      ),
    );
  }
}

enum _ShareAction { pdf, png, print }
