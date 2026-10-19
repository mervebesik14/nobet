import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../logic/block_reason.dart';
import '../../logic/day_shift_planner.dart';
import '../../logic/file_names.dart';
import '../../logic/personal_roster.dart';
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
import '../../shared/providers.dart';
import 'edit_sheet.dart';
import 'personal_roster_pdf.dart';
import 'roster_pdf.dart';
import 'roster_flow.dart';
import 'roster_table.dart';
import 'summary_table.dart';
import '../../shared/app_colors.dart';

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
    return RosterValidator(ref.read(effectiveSettingsProvider)).validate(
      year: plan.year,
      month: plan.month,
      assignments: assignments,
      people: ref.read(peopleProvider),
      unavailableDays: ref.read(effectiveBlockedDaysProvider),
      blockReasons: ref.read(blockReasonsProvider),
      previousMonthTail: ref
          .read(monthPlanProvider.notifier)
          .previousMonthTail(),
      overtimeRequests: plan.overtimeRequests,
      requestedShifts: plan.requestedShifts,
    );
  }

  /// Listeyi onayla sıfırlar; liste boş kaldığı için Ay Planı'na dönülür.
  Future<void> _reset() async {
    setState(() => _swapFrom = null);
    if (await resetRosterFlow(context, ref) && mounted) {
      Navigator.of(context).pop();
    }
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
          .where(
            (p) => p.worksInMonth(_plan.year, _plan.month) && p.role == role,
          )
          .toList()
        ..sort((a, b) => compareTurkish(a.name, b.name));

  Future<void> _onCellTap(RosterCell cell, Role role) async {
    if (_swapFrom != null) return _completeSwap(cell, role);
    if (!_ensureUnlocked()) return;

    // 7A yazan hücre: 7A'yı başkasına vermek ya da 24 nöbete yazmak.
    final dayShift = ref.read(dayShiftsProvider)[cell.day];
    if (dayShift?.personId == cell.personId &&
        !(_plan.assignments[cell.day]?.includes(cell.personId) ?? false)) {
      final choice = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        builder: (context) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text(
                  '${_name(cell.personId)} · ${_dayLabel(cell.day)} · 7A',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              ListTile(
                leading: const Icon(Icons.swap_horiz),
                title: const Text("7A'yı başkasına ver"),
                onTap: () => Navigator.of(context).pop('7a'),
              ),
              ListTile(
                leading: const Icon(Icons.nights_stay_outlined),
                title: const Text('24 nöbete yaz'),
                onTap: () => Navigator.of(context).pop('24'),
              ),
            ],
          ),
        ),
      );
      if (choice == '7a') return _chooseDayShift(cell.day);
      if (choice != '24' || !mounted) return;
    }

    final plan = _plan;
    final settings = ref.read(effectiveSettingsProvider);
    final nursesPerDay = settings.nursesPerDay;
    final twoTechs = settings.techsPerDay >= 2;
    final day = cell.day;
    final id = cell.personId;
    final current = plan.assignments[day] ?? DayAssignment(day: day);
    final before = _currentMessages();

    Map<int, DayAssignment> replace(
      String? oldId,
      String? newId, {
      bool secondary = false,
    }) => RosterEditor.replace(
      plan.assignments,
      day: day,
      role: role,
      oldId: oldId,
      newId: newId,
      nursesPerDay: nursesPerDay,
      secondary: secondary,
    );

    EditOption option(
      String title,
      Map<int, DayAssignment> after,
      String warnFor, {
      IconData? icon,
      String? subtitle,
    }) => EditOption(
      title: title,
      result: after,
      icon: icon,
      subtitle: subtitle,
      warnings: _newWarnings(warnFor, after, before),
    );

    final Map<int, DayAssignment>? result;
    if (current.includes(id)) {
      // Dolu koltuğu düzenle: kişi 24 mü 16B mi oturuyorsa o koltuk.
      final secondary = current.isSecondaryTech(id);
      final shift = role == Role.radiologyTech
          ? (secondary ? ' · 16B' : ' · 24')
          : '';
      result = await showEditSheet(
        context,
        title: '${_name(id)} · ${_dayLabel(day)}$shift',
        actions: [
          EditOption(
            title: 'Nöbeti kaldır',
            subtitle: 'Koltuk boş kalır.',
            icon: Icons.remove_circle_outline,
            result: replace(id, null, secondary: secondary),
          ),
        ],
        candidatesTitle: 'Yerine atanabilecekler',
        candidates: [
          for (final p in _activeOfRole(role))
            if (!current.includes(p.id))
              option(p.name, replace(id, p.id, secondary: secondary), p.id),
        ],
      );
    } else {
      // Kişinin bu güne atanabileceği koltuklar; replaced null = boş koltuk.
      final seats = <({EditOption option, String? replaced})>[];
      void seat(String title, String? replaced, {bool secondary = false}) =>
          seats.add((
            option: option(
              title,
              replace(replaced, id, secondary: secondary),
              id,
            ),
            replaced: replaced,
          ));
      if (role == Role.nurse) {
        if (current.nurseIds.length < nursesPerDay) {
          seat('Boş koltuğa ata', null);
        }
        for (final other in current.nurseIds) {
          seat('${_name(other)} yerine ata', other);
        }
      } else {
        // 24 koltuğu
        if (current.techId == null) {
          seat(twoTechs ? '24 koltuğuna ata' : 'Boş koltuğa ata', null);
        } else {
          seat(
            '${_name(current.techId!)} yerine ata${twoTechs ? ' (24)' : ''}',
            current.techId,
          );
        }
        // 16B koltuğu (yalnız 2 tekniker)
        if (twoTechs) {
          if (current.tech16bId == null) {
            seat('16B koltuğuna ata', null, secondary: true);
          } else {
            seat(
              '${_name(current.tech16bId!)} yerine ata (16B)',
              current.tech16bId,
              secondary: true,
            );
          }
        }
      }

      // "Bu güne ata": önce boş koltuk; yoksa en az yeni uyarı çıkaran,
      // eşitlikte bu ay en çok nöbeti olanın yerine.
      int shiftsOf(String p) =>
          plan.assignments.values.where((a) => a.includes(p)).length;
      // Eşitlikte listedeki ilk koltuk kalır.
      ({EditOption option, String? replaced})? best;
      int rank(({EditOption option, String? replaced}) s) =>
          (s.replaced == null ? 0 : 1) * 10000 +
          s.option.warnings.length * 100 -
          (s.replaced == null ? 0 : shiftsOf(s.replaced!));
      for (final s in seats) {
        if (best == null || rank(s) < rank(best)) best = s;
      }

      result = await showEditSheet(
        context,
        title: '${_name(id)} · ${_dayLabel(day)}',
        actions: [
          if (best != null)
            EditOption(
              title: 'Bu güne ata',
              subtitle: best.replaced == null
                  ? 'Boş koltuğa atanır.'
                  : '${_name(best.replaced!)} yerine atanır.',
              icon: Icons.add_circle_outline,
              result: best.option.result,
              warnings: best.option.warnings,
            ),
        ],
        candidatesTitle: 'Koltuk seç',
        candidates: [for (final s in seats) s.option],
      );
    }
    await _apply(result);
  }

  /// [day] gününün 7A'sını elle başka bir hemşireye verir (ya da otomatik
  /// seçime döndürür). O gün nöbetli, nöbet ertesi, izinli, raporlu, pasif ya
  /// da istemediği günde olanlar uyarıyla birlikte altta listelenir.
  Future<void> _chooseDayShift(int day) async {
    final plan = _plan;
    final current = ref.read(dayShiftsProvider)[day]?.personId;
    // İzin öncesi/sonrası kuralları yalnız 24 nöbeti kapatır, 7A'yı değil.
    final blocked = ref.read(blockReasonsProvider);
    final tail = ref.read(monthPlanProvider.notifier).previousMonthTail();
    bool onDuty(String id, int d) => d < 1
        ? tail.isNotEmpty && tail.last.contains(id)
        : plan.assignments[d]?.includes(id) ?? false;

    final candidates = [
      for (final p in _activeOfRole(Role.nurse))
        if (p.id != current)
          (
            person: p,
            reasons: [
              if (onDuty(p.id, day)) 'o gün nöbetçi',
              if (onDuty(p.id, day - 1)) 'nöbet ertesi',
              if (blocked[p.id]?[day] case final reason?
                  when reason != BlockReason.beforeAnnualLeave &&
                      reason != BlockReason.afterAnnualLeave &&
                      reason != BlockReason.beforeRadiationLeave)
                reason.label,
            ],
          ),
    ]..sort((a, b) => a.reasons.length.compareTo(b.reasons.length));

    const auto = '';
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        final theme = Theme.of(context);
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.6,
          maxChildSize: 0.9,
          builder: (context, controller) => ListView(
            controller: controller,
            children: [
              ListTile(
                title: Text(
                  '${_dayLabel(day)} · 7A',
                  style: theme.textTheme.titleMedium,
                ),
                subtitle: Text(
                  current == null
                      ? 'Şu an 7A boş.'
                      : 'Şu an: ${_name(current)}',
                ),
              ),
              if (plan.dayShiftOverrides.containsKey(day))
                ListTile(
                  leading: const Icon(Icons.auto_mode),
                  title: const Text('Otomatik seçime dön'),
                  onTap: () => Navigator.of(context).pop(auto),
                ),
              for (final c in candidates)
                ListTile(
                  leading: Icon(
                    c.reasons.isEmpty
                        ? Icons.check_circle_outline
                        : Icons.warning_amber_rounded,
                    color: c.reasons.isEmpty
                        ? theme.colorScheme.primary
                        : Colors.orange,
                  ),
                  title: Text(c.person.name),
                  subtitle: c.reasons.isEmpty
                      ? null
                      : Text(c.reasons.join(', ')),
                  onTap: () => Navigator.of(context).pop(c.person.id),
                ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
    if (picked == null) return;
    await ref
        .read(monthPlanProvider.notifier)
        .setDayShiftOverride(day, picked == auto ? null : picked);
  }

  Future<void> _onMissingTap(int day) async {
    if (_swapFrom != null) {
      _notify('Takas için başka bir nöbete (24) dokunun.');
      return;
    }
    if (!_ensureUnlocked()) return;
    final plan = _plan;
    final settings = ref.read(effectiveSettingsProvider);
    final current = plan.assignments[day] ?? DayAssignment(day: day);
    final before = _currentMessages();

    // Boş koltuklar: hemşire, 24 teknikeri, 16B teknikeri.
    final slots = <({Role role, bool secondary, String label})>[
      if (current.nurseIds.length < settings.nursesPerDay)
        (role: Role.nurse, secondary: false, label: 'Hemşire'),
      if (settings.techsPerDay >= 1 && current.techId == null)
        (
          role: Role.radiologyTech,
          secondary: false,
          label: settings.techsPerDay >= 2
              ? '24 teknikeri'
              : 'Radyoloji Teknikeri',
        ),
      if (settings.techsPerDay >= 2 && current.tech16bId == null)
        (role: Role.radiologyTech, secondary: true, label: '16B teknikeri'),
    ];
    final candidates = <EditOption>[];
    for (final slot in slots) {
      for (final p in _activeOfRole(slot.role)) {
        if (current.includes(p.id)) continue;
        final after = RosterEditor.replace(
          plan.assignments,
          day: day,
          role: slot.role,
          newId: p.id,
          nursesPerDay: settings.nursesPerDay,
          secondary: slot.secondary,
        );
        candidates.add(
          EditOption(
            title: '${p.name} (${slot.label})',
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
        nursesPerDay: ref.read(effectiveSettingsProvider).nursesPerDay,
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
  /// Kişi seçtirip o kişinin aylık nöbetlerini, her nöbet günündeki tüm
  /// hemşire ve radyoloji nöbetçileriyle birlikte metin olarak paylaşır.
  Future<void> _sharePersonal(
    List<RosterRow> rows,
    Map<int, DayShift> dayShifts, {
    required bool asPdf,
    required Set<int> weekendDays,
    required Set<int> holidayDays,
  }) async {
    final picked = await showDialog<RosterRow>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Kimin listesi?'),
        children: [
          for (final r in rows)
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(r),
              child: Text(r.name),
            ),
        ],
      ),
    );
    if (picked == null || !mounted) return;
    final plan = _plan;
    final person =
        _peopleById[picked.id] ??
        Person(id: picked.id, name: picked.name, role: picked.role);
    final services = ref.read(platformServicesProvider);
    final monthLabel = DateFormat.yMMMM(
      'tr_TR',
    ).format(DateTime(plan.year, plan.month));
    try {
      if (asPdf) {
        final fonts = await services.loadPdfFonts();
        final pdf = await buildPersonalRosterPdf(
          data: PersonalRoster.build(
            plan: plan,
            person: person,
            people: ref.read(peopleProvider),
            dayShifts: dayShifts,
            weekendDays: weekendDays,
          ),
          weekendDays: weekendDays,
          holidayDays: holidayDays,
          font: fonts.regular,
          boldFont: fonts.bold,
          createdAt: ref.read(todayProvider),
        );
        await services.sharePdf(
          pdf,
          'nobet-${fileSlug(person.name)}-${plan.year}-'
          '${plan.month.toString().padLeft(2, '0')}.pdf',
        );
      } else {
        await services.shareText(
          PersonalRoster.text(
            plan: plan,
            person: person,
            people: ref.read(peopleProvider),
            dayShifts: dayShifts,
          ),
          subject: '${person.name} · $monthLabel nöbetleri',
        );
      }
    } catch (e) {
      if (mounted) _notify('Paylaşılamadı: $e');
    }
  }

  Future<void> _share(
    _ShareAction action, {
    required MonthPlan plan,
    required List<RosterRow> rows,
    required RosterSummary summary,
    required Set<int> weekendDays,
    required Set<int> holidayDays,
    required Map<int, int> missingByDay,
    required int shiftHours,
    required Map<int, DayShift> dayShifts,
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
        dayShifts: dayShifts,
        font: fonts.regular,
        boldFont: fonts.bold,
        singlePage: action == _ShareAction.png,
      );
      switch (action) {
        case _ShareAction.personal || _ShareAction.personalPdf:
          return;
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
    // Yalnız hemşire ayında teknikeri kapatılmış etkin ayarlar kullanılır.
    final settings = ref.watch(effectiveSettingsProvider);
    final violations = ref.watch(rosterViolationsProvider);
    final dayShifts = ref.watch(dayShiftsProvider);
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
      onlyRoles: plan.nurseOnly ? const {Role.nurse} : null,
      leaveDays: plan.leaveDays,
      dayShifts: dayShifts,
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
            onSelected: (action) => switch (action) {
              _ShareAction.personal ||
              _ShareAction.personalPdf => _sharePersonal(
                rows,
                dayShifts,
                asPdf: action == _ShareAction.personalPdf,
                weekendDays: weekendDays,
                holidayDays: holidayDays,
              ),
              _ => _share(
                action,
                plan: plan,
                rows: rows,
                summary: summary,
                weekendDays: weekendDays,
                holidayDays: holidayDays,
                missingByDay: missingByDay,
                shiftHours: settings.shiftHours,
                dayShifts: dayShifts,
              ),
            },
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
              PopupMenuItem(
                value: _ShareAction.personalPdf,
                child: ListTile(
                  leading: Icon(Icons.badge_outlined),
                  title: Text('Kişiye özel liste (PDF)'),
                ),
              ),
              PopupMenuItem(
                value: _ShareAction.personal,
                child: ListTile(
                  leading: Icon(Icons.person_outline),
                  title: Text('Kişiye özel liste (mesaj)'),
                ),
              ),
            ],
          ),
          IconButton(
            tooltip: 'Listeyi sıfırla',
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed: _reset,
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
              tileColor: theme.colorScheme.headerTint,
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
              dayShifts: dayShifts,
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

/// Kural ihlalleri, önem sırasıyla ayrı kutularda: boş günler (en üstte),
/// izinli ya da istemediği günde çalışanlar ve (elle düzenlemeden doğan) diğer ihlaller.
class _ViolationList extends StatelessWidget {
  const _ViolationList({required this.violations});

  final List<RuleViolation> violations;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    if (violations.isEmpty) {
      return ListTile(
        leading: Icon(Icons.check_circle_outline, color: scheme.primary),
        title: const Text('Kural ihlali yok'),
      );
    }
    final missing = [
      for (final v in violations)
        if (v.kind == ViolationKind.missing) v,
    ];
    final unavailable = [
      for (final v in violations)
        if (v.kind == ViolationKind.unavailable) v,
    ];
    final other = [
      for (final v in violations)
        if (v.kind != ViolationKind.missing &&
            v.kind != ViolationKind.unavailable)
          v,
    ];
    const warning = Color(0xFFB26A00);
    return Column(
      children: [
        if (missing.isNotEmpty)
          _ViolationCard(
            key: const ValueKey('violations-missing'),
            title: 'Boş günler',
            icon: Icons.event_busy,
            color: scheme.error,
            background: scheme.dangerTint,
            items: missing,
          ),
        if (unavailable.isNotEmpty)
          _ViolationCard(
            key: const ValueKey('violations-unavailable'),
            title: 'İzinli / istemediği günde çalışanlar',
            icon: Icons.person_off_outlined,
            color: warning,
            background: scheme.holidayTint,
            items: unavailable,
          ),
        if (other.isNotEmpty)
          _ViolationCard(
            key: const ValueKey('violations-other'),
            title: 'Diğer kural ihlalleri',
            icon: Icons.warning_amber_rounded,
            color: warning,
            background: scheme.holidayTint,
            items: other,
          ),
      ],
    );
  }
}

class _ViolationCard extends StatelessWidget {
  const _ViolationCard({
    super.key,
    required this.title,
    required this.icon,
    required this.color,
    required this.background,
    required this.items,
  });

  final String title;
  final IconData icon;
  final Color color;
  final Color background;
  final List<RuleViolation> items;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      color: background,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              leading: Icon(icon, color: color),
              title: Text(
                '$title (${items.length})',
                style: TextStyle(color: color, fontWeight: FontWeight.w600),
              ),
            ),
            for (final v in items)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('• ${v.message}', style: TextStyle(color: color)),
                    // Boş koltukta kimin neden yazılamadığı.
                    if (v.detail case final detail?)
                      Padding(
                        padding: const EdgeInsets.only(left: 12, top: 2),
                        child: Text(
                          detail,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

enum _ShareAction { pdf, png, print, personalPdf, personal }
