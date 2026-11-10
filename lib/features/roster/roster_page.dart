import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../logic/backup_picker.dart';
import '../../logic/block_reason.dart';
import '../../logic/day_shift_planner.dart';
import '../../logic/file_names.dart';
import '../../logic/personal_roster.dart';
import '../../logic/phone_number.dart';
import '../../logic/roster_calendar.dart';
import '../../logic/roster_editor.dart';
import '../../logic/roster_excel.dart';
import '../../logic/roster_generator.dart';
import '../../logic/roster_summary.dart';
import '../../logic/roster_validator.dart';
import '../../logic/shift_explainer.dart';
import '../../logic/shift_pay.dart';
import '../../logic/swap_finder.dart';
import '../../logic/shift_gaps.dart';
import '../../logic/text_edits.dart';
import '../../logic/summary_columns.dart';
import '../../logic/turkish_collation.dart';
import '../../logic/turkish_dates.dart';
import '../../logic/xlsx_writer.dart';
import '../../models/models.dart';
import '../holidays/holidays_controller.dart';
import '../month/month_plan_controller.dart';
import '../people/people_controller.dart';
import '../../data/providers.dart';
import '../../shared/calendar_service.dart';
import '../../shared/person_colors.dart';
import '../../shared/platform_services.dart';
import '../../shared/providers.dart';
import '../../shared/widgets/motion.dart';
import 'change_notice_page.dart';
import 'edit_sheet.dart';
import '../settings/report_info.dart';
import 'overtime_report_pdf.dart';
import 'personal_roster_pdf.dart';
import 'swap_log_page.dart';
import 'person_calendar_page.dart';
import 'text_edit_page.dart';
import 'what_if_page.dart';
import 'whatsapp_send_page.dart';
import 'roster_history_page.dart';
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
  const RosterPage({super.key, this.freeEdit = false});

  /// Serbest düzenleme açık başlasın (elle giriş sonrası).
  final bool freeEdit;

  @override
  ConsumerState<RosterPage> createState() => _RosterPageState();
}

class _RosterPageState extends ConsumerState<RosterPage> {
  /// Takas modunda seçilen ilk nöbet.
  RosterCell? _swapFrom;

  /// "Kurallara göre düzelt" çalışıyor mu?
  bool _fixing = false;

  /// Serbest düzenleme: dokununca doğrudan ekle / sil.
  late bool _freeEdit = widget.freeEdit;

  /// Tabloda vurgulanan kişi (adına dokunulunca).
  String? _highlightId;

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
      absentDays: plan.leaveDays,
    );
  }

  /// Vurgulanan kişinin bu ayki kısa özeti.
  List<String> _personStats(
    String id,
    Set<int> weekendDays,
    Iterable<DayShift> dayShifts,
  ) {
    final plan = _plan;
    final days = {
      for (final a in plan.assignments.values)
        if (a.includes(id)) a.day,
    };
    final absent = {
      ...plan.leaveDaysOf(id),
      ...?_peopleById[id]?.inactiveDaysIn(plan.year, plan.month),
    };
    final longest = ShiftGaps.longest(
      days,
      absent: absent,
      monthEnd: plan.daysInMonth,
    );
    final dayShiftCount = dayShifts.where((s) => s.personId == id).length;
    return [
      '${days.length} nöbet',
      '${days.where(weekendDays.contains).length} hafta sonu',
      '${RosterGenerator.everyOtherDayPairs(days)} gün aşırı',
      if (longest != null) 'en uzun boşluk $longest gün',
      '4–5 gün ara: ${ShiftGaps.longCount(days, absent: absent)}',
      if (dayShiftCount > 0) '$dayShiftCount gün 7A',
      if (absent.isNotEmpty) '${absent.length} gün izinli/pasif',
    ];
  }

  /// Serbest düzenleme: kişiyi o güne doğrudan ekler ya da siler.
  Future<void> _toggleCell(RosterCell cell, Role role) async {
    final plan = _plan;
    final had = plan.assignments[cell.day]?.includes(cell.personId) ?? false;
    try {
      final result = RosterEditor.toggle(
        plan.assignments,
        day: cell.day,
        personId: cell.personId,
        role: role,
        twoTechs: ref.read(effectiveSettingsProvider).techsPerDay >= 2,
      );
      if (!await _confirmViolations(result)) return;
      await _apply(
        result,
        message:
            '${_name(cell.personId)} ${formatDayMonth(cell.day, plan.month)} '
            '${had ? 'nöbetinden çıkarıldı' : 'nöbetine yazıldı'}.',
      );
    } on RosterEditException catch (e) {
      _notify(e.message);
    }
  }

  /// Listeyi baştan kurmadan kural bozan nöbetleri en az değişiklikle
  /// düzeltir; sonuç geçmişe yazılır ve geri alınabilir.
  Future<void> _fixRoster() async {
    setState(() {
      _fixing = true;
      _swapFrom = null;
    });
    final controller = ref.read(monthPlanProvider.notifier);
    final outcome = await controller.fixRoster();
    if (!mounted) return;
    setState(() => _fixing = false);
    if (outcome == null) return;
    final changed = outcome.changed;
    final empty = outcome.result.issues.length;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            changed == 0
                ? 'Değiştirilecek nöbet bulunamadı; kalan uyarılar kişi '
                      'sayısı ya da izinler yüzünden giderilemiyor.'
                : '$changed nöbet değişti.'
                      '${empty > 0 ? ' $empty koltuk boş kaldı.' : ''}',
          ),
          action: changed == 0
              ? null
              : SnackBarAction(
                  label: 'Geri al',
                  onPressed: () => controller.undoLast(),
                ),
        ),
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

  /// Elle düzenlemede onay istenen kurallar. Boşluk uyarıları listede
  /// görünür ama onay istemez: liste elle doldurulurken neredeyse her
  /// adımda geçici olarak çıkarlar.
  static const _confirmedKinds = {
    ViolationKind.unavailable,
    ViolationKind.consecutive,
    ViolationKind.chain,
    ViolationKind.overCap,
    ViolationKind.wrongRole,
    ViolationKind.chargeNurseUnrequested,
  };

  /// [after] uygulanırsa yeni çıkacak kural ihlallerini gösterip onay
  /// ister; ihlal yoksa ya da "Yine de yap" denirse true.
  Future<bool> _confirmViolations(Map<int, DayAssignment> after) async {
    final before = _currentMessages();
    final added = [
      for (final v in _validate(after))
        if (_confirmedKinds.contains(v.kind) && !before.contains(v.message))
          v.message,
    ];
    return _confirmWarnings(added);
  }

  /// [warnings] varsa gösterip onay ister; yoksa ya da "Yine de yap"
  /// denirse true.
  Future<bool> _confirmWarnings(List<String> warnings) async {
    final added = warnings;
    if (added.isEmpty) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded, color: Colors.orange),
        title: const Text('Kural ihlali'),
        content: SingleChildScrollView(
          child: Text(
            '${added.map((m) => '• $m').join('\n')}\n\nYine de yapılsın mı?',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Yine de yap'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  /// Nöbeti siler (koltuk boş kalır).
  Future<void> _deleteShift(RosterCell cell, Role role) async {
    final plan = _plan;
    try {
      final result = RosterEditor.replace(
        plan.assignments,
        day: cell.day,
        role: role,
        oldId: cell.personId,
        newId: null,
        nursesPerDay: ref.read(effectiveSettingsProvider).nursesPerDay,
        secondary:
            plan.assignments[cell.day]?.isSecondaryTech(cell.personId) ?? false,
      );
      if (!await _confirmViolations(result)) return;
      await _apply(
        result,
        message:
            '${_name(cell.personId)} ${formatDayMonth(cell.day, plan.month)} '
            'nöbetinden çıkarıldı.',
      );
    } on RosterEditException catch (e) {
      _notify(e.message);
    }
  }

  bool _ensureUnlocked() {
    if (!_plan.isLocked) return true;
    _notify('Liste kilitli; düzenlemek için kilidi açın.');
    return false;
  }

  /// Düzenlemeyi kaydeder ve "Geri al" seçenekli bildirim gösterir.
  Future<void> _apply(
    Map<int, DayAssignment>? result, {
    String message = 'Değişiklik kaydedildi.',
    Map<int, String>? dayShiftOverrides,
    Map<String, List<int>>? techDayShifts,
  }) async {
    if (result == null) return;
    final controller = ref.read(monthPlanProvider.notifier);
    await controller.setAssignments(
      result,
      dayShiftOverrides: dayShiftOverrides,
      techDayShifts: techDayShifts,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: SuccessMessage(message),
          action: SnackBarAction(
            label: 'Geri al',
            onPressed: () => controller.undoLast(),
          ),
        ),
      );
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
    final onShiftHere =
        _plan.assignments[cell.day]?.includes(cell.personId) ?? false;
    // Serbest düzenlemede de 7A hücresi 7A seçeneklerini açar (silmek için).
    final shows7A =
        !onShiftHere &&
        (dayShift?.personId == cell.personId || _techHas7A(cell, role));
    // Serbest düzenlemede mesai günü dokundukça: boş → 24 → 7A → boş
    // (sorumlu hemşire 7A'ya çevrilmez; hafta sonu/tatilde 24 → boş).
    if (_freeEdit && _techHas7A(cell, role)) return _removeTechDayShift(cell);
    if (_freeEdit &&
        _plan.assignments[cell.day]?.extraShiftOf(cell.personId) != null) {
      return _setExtraShift(cell, null);
    }
    if (_freeEdit && onShiftHere && _isWorkday(cell.day) && !_isCharge(cell)) {
      return _writeTechDayShift(cell);
    }
    if (_freeEdit && !shows7A) return _toggleCell(cell, role);

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
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text("7A'yı sil"),
                subtitle: const Text(
                  'O gün 7A kimseye yazılmaz; istersen sonra bir hemşirenin '
                  'hücresine dokunup 7A yazabilirsin.',
                ),
                onTap: () => Navigator.of(context).pop('delete'),
              ),
            ],
          ),
        ),
      );
      if (choice == '7a') return _chooseDayShift(cell.day);
      if (choice == 'delete') return _deleteDayShift(cell);
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
      final code = current.shiftCode(id);
      final shift = role == Role.radiologyTech || code != '24'
          ? ' · $code'
          : '';
      result = await showEditSheet(
        context,
        title: '${_name(id)} · ${_dayLabel(day)}$shift',
        actions: [
          EditOption(
            title: 'Gelemiyor: yedeği yaz',
            subtitle: 'Kurala uyan yedeklerden biri yerine yazılır.',
            icon: Icons.sick_outlined,
            result: plan.assignments,
            onSelected: () => _useBackup(cell, role),
          ),
          EditOption(
            title: 'Takas önerileri',
            subtitle: 'Kural bozmadan değişebileceği nöbetler.',
            icon: Icons.swap_horiz,
            result: plan.assignments,
            onSelected: () => _showSwapSuggestions(cell),
          ),
          EditOption(
            title: 'Neden bu nöbet?',
            subtitle: 'Neden bu kişi, neden başkası değil.',
            icon: Icons.help_outline,
            result: plan.assignments,
            onSelected: () => _showWhy(cell),
          ),
          EditOption(
            title: 'Nöbeti kaldır',
            subtitle: 'Koltuk boş kalır.',
            icon: Icons.remove_circle_outline,
            result: replace(id, null, secondary: secondary),
          ),
          ..._dayShiftOptions(cell, role),
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
          ..._dayShiftOptions(cell, role),
        ],
        candidatesTitle: 'Koltuk seç',
        candidates: [for (final s in seats) s.option],
      );
    }
    await _apply(result);
  }

  /// [cell] gününün (sorumlu hemşire planından gelen) 7A'sını siler: o gün
  /// 7A kimseye yazılmaz.
  Future<void> _deleteDayShift(RosterCell cell) async {
    final plan = _plan;
    final controller = ref.read(monthPlanProvider.notifier);
    if (!await controller.setDayShiftOverride(cell.day, '')) return;
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            '${_name(cell.personId)} ${formatDayMonth(cell.day, plan.month)} '
            '7A silindi.',
          ),
          action: SnackBarAction(
            label: 'Geri al',
            onPressed: () => controller.undoLast(),
          ),
        ),
      );
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
                      reason != BlockReason.beforeRadiationLeave &&
                      reason != BlockReason.afterRadiationLeave)
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

  /// Kişinin [cell] gününde elle (ek) 7A'sı var mı (o gün nöbette
  /// değilken)? Teknikerde ve hemşirede (sorumlunun 7A'sına ek).
  bool _techHas7A(RosterCell cell, Role role) =>
      !(_plan.assignments[cell.day]?.includes(cell.personId) ?? false) &&
      (_plan.techDayShifts[cell.personId]?.contains(cell.day) ?? false);

  /// [cell] kişisine o gün 7A yazılabilir mi? Hemşire: sorumlu hemşire
  /// tanımlıyken mesai günü ve o günün 7A'sı zaten onda değilse. Tekniker:
  /// mesai günü ve henüz 7A'sı yoksa.
  /// [day] mesai günü mü (hafta sonu / tam gün tatil değil)?
  bool _isWorkday(int day) =>
      DayShiftPlanner.workdayHours(
        year: _plan.year,
        month: _plan.month,
        day: day,
        holidays: ref.read(holidaysProvider),
        settings: ref.read(effectiveSettingsProvider),
      ) !=
      null;

  bool _isCharge(RosterCell cell) => ref
      .read(peopleProvider)
      .any((p) => p.id == cell.personId && p.isChargeNurse);

  bool _can7A(RosterCell cell, Role role) {
    final plan = _plan;
    if (role == Role.nurse) {
      final isDayShift =
          ref.read(dayShiftsProvider)[cell.day]?.personId == cell.personId;
      return !isDayShift && _hasDayShiftSlot(cell.day);
    }
    final workday =
        DayShiftPlanner.workdayHours(
          year: plan.year,
          month: plan.month,
          day: cell.day,
          holidays: ref.read(holidaysProvider),
          settings: ref.read(effectiveSettingsProvider),
        ) !=
        null;
    return workday && !_techHas7A(cell, role);
  }

  /// Hemşireye ek 7A yazılabilir mi? Mesai günü, o günün (sorumlu) 7A'sı
  /// onda değil ve elle 7A'sı yok.
  bool _canExtra7A(RosterCell cell, Role role) {
    if (role != Role.nurse) return false;
    final plan = _plan;
    final workday =
        DayShiftPlanner.workdayHours(
          year: plan.year,
          month: plan.month,
          day: cell.day,
          holidays: ref.read(holidaysProvider),
          settings: ref.read(effectiveSettingsProvider),
        ) !=
        null;
    final isDayShift =
        ref.read(dayShiftsProvider)[cell.day]?.personId == cell.personId;
    return workday && !isDayShift && !_techHas7A(cell, role);
  }

  /// Dokununca açılan sayfadaki 7A seçenekleri.
  List<EditOption> _dayShiftOptions(RosterCell cell, Role role) {
    final plan = _plan;
    final onShift =
        plan.assignments[cell.day]?.includes(cell.personId) ?? false;
    final nurse = role == Role.nurse;
    return [
      if (_techHas7A(cell, role))
        EditOption(
          title: "7A'yı kaldır",
          icon: Icons.wb_sunny_outlined,
          result: plan.assignments,
          onSelected: () => _removeTechDayShift(cell),
        ),
      if (_canExtra7A(cell, role))
        EditOption(
          title: onShift ? "Ek 7A'ya çevir" : 'Ek 7A yaz',
          subtitle: onShift
              ? '24 nöbeti kalkar; sorumlunun 7A\'sına ek olarak 7A çalışır.'
              : 'Sorumlunun 7A\'sı kalır; bu kişi de 7A çalışır.',
          icon: Icons.add_task,
          result: plan.assignments,
          onSelected: () => _writeTechDayShift(cell),
        ),
      if (_can7A(cell, role))
        EditOption(
          title: onShift ? "7A'ya çevir" : '7A yaz',
          subtitle: onShift
              ? (nurse
                    ? '24 nöbeti kalkar, bu günün 7A\'sına yazılır.'
                    : 'Nöbeti kalkar, bu gün 7A (gündüz) çalışır.')
              : (nurse
                    ? 'Bu günün 7A\'sı bu kişiye geçer.'
                    : 'Gündüz mesaisi, günün mesai saati kadar.'),
          icon: Icons.wb_sunny_outlined,
          result: plan.assignments,
          onSelected: () =>
              nurse ? _writeDayShift(cell) : _writeTechDayShift(cell),
        ),
      ..._customShiftOptions(cell, role),
    ];
  }

  /// Ayarlar'da tanımlı özel mesailer (ör. 19A) için seçenekler: koltuktaki
  /// kişinin vardiyasını çevirmek, boş hücreye yazmak, ek mesaiyi kaldırmak.
  List<EditOption> _customShiftOptions(RosterCell cell, Role role) {
    final plan = _plan;
    final defs = ref.read(rosterSettingsProvider).customShifts;
    final current = plan.assignments[cell.day] ?? DayAssignment(day: cell.day);
    final id = cell.personId;
    final onShift = current.includes(id);
    final mainSeat = current.nurseIds.contains(id) || current.techId == id;
    final code = current.customShiftOf(id);
    final extra = current.extraShiftOf(id);
    EditOption action(
      String title,
      Future<void> Function() run, {
      String? subtitle,
      IconData icon = Icons.more_time,
    }) => EditOption(
      title: title,
      subtitle: subtitle,
      icon: icon,
      result: plan.assignments,
      onSelected: run,
    );
    return [
      if (extra != null)
        action(
          '$extra mesaisini kaldır',
          () => _setExtraShift(cell, null),
          icon: Icons.remove_circle_outline,
        ),
      if (code != null)
        action(
          '24 olarak değiştir',
          () => _setCustomShift(cell, null),
          subtitle: '$code yerine 24 nöbet tutar.',
        ),
      for (final def in defs)
        if (def.fillsSeat) ...[
          if (mainSeat && code != def.code)
            action(
              '${def.code} olarak değiştir',
              () => _setCustomShift(cell, def.code),
              subtitle: def.description,
            ),
          if (!onShift)
            action(
              '${def.code} yaz',
              () => _write16a(cell, role, code: def.code),
              subtitle:
                  '${def.description}; '
                  '${role == Role.nurse ? 'bir hemşire koltuğunu' : '24 koltuğunu'} '
                  'doldurur.',
            ),
        ] else if (extra != def.code)
          action(
            onShift ? '${def.code} olarak değiştir' : '${def.code} yaz',
            () => _setExtraShift(cell, def.code),
            subtitle: onShift
                ? 'Nöbeti kalkar; ${def.description}.'
                : def.description,
          ),
    ];
  }

  /// "Ya şöyle olursa" deneme sayfası; uygulanırsa bildirim gösterilir.
  Future<void> _whatIf() async {
    if (!_ensureUnlocked()) return;
    setState(() => _swapFrom = null);
    final message = await Navigator.of(
      context,
    ).push<String>(MaterialPageRoute(builder: (_) => const WhatIfPage()));
    if (message != null && mounted) _notify(message);
  }

  /// Yazarak düzenleme: komutlar tek seferde uygulanır (tek "Geri al").
  Future<void> _textEdit() async {
    if (!_ensureUnlocked()) return;
    setState(() => _swapFrom = null);
    final plan = _plan;
    final settings = ref.read(effectiveSettingsProvider);
    final edits = await Navigator.of(context).push<List<TextEdit>>(
      MaterialPageRoute(
        builder: (_) => TextEditPage(
          plan: plan,
          people: ref.read(peopleProvider),
          codes: [for (final c in settings.customShifts) c.code],
        ),
      ),
    );
    if (edits == null || edits.isEmpty || !mounted) return;
    final r = TextEdits.apply(
      plan: plan,
      edits: edits,
      settings: settings,
      holidays: ref.read(holidaysProvider),
    );
    if (r.errors.isNotEmpty) {
      final go = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Bazıları uygulanamadı'),
          content: Text(
            '${r.errors.map((e) => '• $e').join('\n')}'
            '${r.done.isEmpty ? '' : '\n\nKalan ${r.done.length} değişiklik uygulansın mı?'}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Vazgeç'),
            ),
            if (r.done.isNotEmpty)
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Uygula'),
              ),
          ],
        ),
      );
      if (go != true || !mounted) return;
    }
    if (r.done.isEmpty) return;
    if (!await _confirmViolations(r.assignments)) return;
    await _apply(
      r.assignments,
      techDayShifts: r.techDayShifts,
      message: r.done.length == 1
          ? r.done.single
          : '${r.done.length} değişiklik uygulandı.',
    );
  }

  /// Nöbetçi gelemiyor: kurala uyan yedeklerden biri seçilir, yerine
  /// yazılır; istenirse o güne rapor işlenir ve yedeğe mesaj hazırlanır.
  Future<void> _useBackup(RosterCell cell, Role role) async {
    if (!_ensureUnlocked()) return;
    final plan = _plan;
    final settings = ref.read(effectiveSettingsProvider);
    final current = plan.assignments[cell.day];
    if (current == null || !current.includes(cell.personId)) return;
    final backups = BackupPicker.candidates(
      plan: plan,
      people: ref.read(peopleProvider),
      day: cell.day,
      role: role,
      settings: settings,
      blockReasons: ref.read(blockReasonsProvider),
      weekendDays: RosterGenerator.weekendDays(
        plan.year,
        plan.month,
        ref.read(holidaysProvider),
        settings,
      ),
      count: 3,
    );
    if (backups.isEmpty) {
      _notify('Bu gün için kurala uyan yedek yok; listeden elle seçin.');
      return;
    }
    var sick = true;
    final picked = await showDialog<Person>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text(
            '${_name(cell.personId)} yerine kim? · ${_dayLabel(cell.day)}',
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final (i, p) in backups.indexed)
                ListTile(
                  key: ValueKey('backup-${p.id}'),
                  leading: Icon(i == 0 ? Icons.star : Icons.person_outline),
                  title: Text(p.name),
                  subtitle: i == 0 ? const Text('Önerilen yedek') : null,
                  onTap: () => Navigator.of(context).pop(p),
                ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Rapor işle'),
                subtitle: Text(
                  '${_name(cell.personId)} için ${_dayLabel(cell.day)} rapor '
                  'günü olarak kaydedilir.',
                ),
                value: sick,
                onChanged: (v) => setLocal(() => sick = v),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Vazgeç'),
            ),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;
    final after = RosterEditor.replace(
      plan.assignments,
      day: cell.day,
      role: role,
      oldId: cell.personId,
      newId: picked.id,
      nursesPerDay: settings.nursesPerDay,
      secondary: current.isSecondaryTech(cell.personId),
    );
    final controller = ref.read(monthPlanProvider.notifier);
    if (sick &&
        !plan.leaveOf(cell.personId, LeaveType.sick).contains(cell.day)) {
      await controller.toggleLeave(cell.personId, LeaveType.sick, cell.day);
    }
    if (!mounted) return;
    await _apply(
      after,
      message:
          '${formatDayMonth(cell.day, plan.month)}: ${_name(cell.personId)} '
          'yerine ${picked.name}.',
    );
    if (!mounted) return;
    final text = BackupPicker.message(
      plan: plan,
      day: cell.day,
      backupName: picked.name,
      absentName: _name(cell.personId),
      shift: after[cell.day]!.shiftCode(picked.id),
    );
    final tell = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${picked.name}: haber verilsin mi?'),
        content: Text(text),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Sonra'),
          ),
          FilledButton(
            key: const ValueKey('backup-message'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Mesaj gönder'),
          ),
        ],
      ),
    );
    if (tell != true || !mounted) return;
    final services = ref.read(platformServicesProvider);
    final number = PhoneNumber.normalize(picked.phone);
    final opened =
        number != null &&
        (await services.openUrl(PhoneNumber.whatsApp(number, text)) ||
            await services.openUrl(PhoneNumber.whatsAppWeb(number, text)));
    if (!opened) await services.shareText(text);
  }

  /// Takas önerileri: kural bozmadan değişebileceği nöbetler; "Takas"
  /// uygular, mesaj simgesi öteki kişiye teklif gönderir.
  Future<void> _showSwapSuggestions(RosterCell cell) async {
    if (!_ensureUnlocked()) return;
    final plan = _plan;
    final settings = ref.read(effectiveSettingsProvider);
    final people = ref.read(peopleProvider);
    final options = SwapFinder.find(
      plan: plan,
      people: people,
      personId: cell.personId,
      day: cell.day,
      nursesPerDay: settings.nursesPerDay,
      validate: _validate,
      weekendDays: RosterGenerator.weekendDays(
        plan.year,
        plan.month,
        ref.read(holidaysProvider),
        settings,
      ),
    );
    final byId = {for (final p in people) p.id: p};
    final name = _name(cell.personId);
    String d(int x) => formatDayMonthWeekday(plan.year, plan.month, x);
    final picked = await showModalBottomSheet<SwapOption>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        final theme = Theme.of(context);
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.8,
            ),
            child: ListView(
              key: const ValueKey('swap-sheet'),
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              children: [
                Text(
                  '$name · ${d(cell.day)} · takas önerileri',
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  options.isEmpty
                      ? 'Kural bozmadan yapılabilecek takas bulunamadı. '
                            '"Başka bir nöbetle takas et" ile elle '
                            'seçebilirsiniz.'
                      : 'Hiçbiri yeni kural ihlali doğurmaz; yakın tarihler '
                            'önce.',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                for (final o in options)
                  ListTile(
                    key: ValueKey('swap-${o.otherId}-${o.otherDay}'),
                    contentPadding: EdgeInsets.zero,
                    leading: byId[o.otherId] == null
                        ? null
                        : PersonAvatar.of(byId[o.otherId]!, radius: 18),
                    title: Text('${o.otherName} · ${d(o.otherDay)}'),
                    subtitle: Text(
                      '$name → ${formatDayMonth(o.otherDay, plan.month)} · '
                      '${o.otherName} → ${formatDayMonth(cell.day, plan.month)}',
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Teklif gönder',
                          icon: const Icon(Icons.send_outlined),
                          onPressed: () => _sendSwapOffer(cell, o),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.of(context).pop(o),
                          child: const Text('Takas'),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
    if (picked == null || !mounted) return;
    await _apply(
      picked.after,
      message:
          'Takas: $name ${formatDayMonth(cell.day, plan.month)} ↔ '
          '${picked.otherName} ${formatDayMonth(picked.otherDay, plan.month)}.',
    );
  }

  /// Takas teklifini öteki kişiye gönderir (numarası varsa WhatsApp).
  Future<void> _sendSwapOffer(RosterCell cell, SwapOption o) async {
    final plan = _plan;
    final other = ref
        .read(peopleProvider)
        .where((p) => p.id == o.otherId)
        .firstOrNull;
    final text = SwapFinder.offer(
      plan: plan,
      personName: _name(cell.personId),
      day: cell.day,
      otherName: o.otherName,
      otherDay: o.otherDay,
    );
    final services = ref.read(platformServicesProvider);
    final number = PhoneNumber.normalize(other?.phone);
    final opened =
        number != null &&
        (await services.openUrl(PhoneNumber.whatsApp(number, text)) ||
            await services.openUrl(PhoneNumber.whatsAppWeb(number, text)));
    if (!opened) await services.shareText(text);
  }

  /// "Neden bu nöbet?": kişinin bu ayki durumu ve aynı roldeki diğerlerinin
  /// o gün neden nöbette olmadığı.
  Future<void> _showWhy(RosterCell cell) async {
    final plan = _plan;
    final x = ShiftExplainer.explain(
      plan: plan,
      people: ref.read(peopleProvider),
      personId: cell.personId,
      day: cell.day,
      settings: ref.read(effectiveSettingsProvider),
      blockReasons: ref.read(blockReasonsProvider),
      weekendDays: RosterGenerator.weekendDays(
        plan.year,
        plan.month,
        ref.read(holidaysProvider),
        ref.read(effectiveSettingsProvider),
      ),
    );
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        final theme = Theme.of(context);
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.8,
            ),
            child: ListView(
              key: const ValueKey('why-sheet'),
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              children: [
                Text(x.title, style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                for (final w in x.warnings)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      w,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ),
                for (final f in x.facts)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text('• $f'),
                  ),
                if (x.others.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Neden başkası değil?',
                    style: theme.textTheme.titleSmall,
                  ),
                  for (final o in x.others)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(o.name),
                      subtitle: Text(o.reason),
                    ),
                ],
                const SizedBox(height: 8),
                Text(
                  'Açıklama listenin şu anki hâline göredir; elle yapılan '
                  'değişiklikler de hesaba katılır.',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Koltuktaki kişinin vardiyasını özel mesai [code] yapar (null → 24).
  Future<void> _setCustomShift(RosterCell cell, String? code) async {
    final plan = _plan;
    try {
      final after = RosterEditor.setCustomShift(
        plan.assignments,
        day: cell.day,
        personId: cell.personId,
        code: code,
      );
      await _apply(
        after,
        message:
            '${_name(cell.personId)} ${formatDayMonth(cell.day, plan.month)} '
            '${code ?? '24'} olarak değiştirildi.',
      );
    } on RosterEditException catch (e) {
      _notify(e.message);
    }
  }

  /// Kişiye [cell] gününde ek özel mesai [code] yazar (null → kaldırır).
  /// Kişi o gün nöbetteyse nöbeti kalkar.
  Future<void> _setExtraShift(RosterCell cell, String? code) async {
    final plan = _plan;
    final current = plan.assignments[cell.day];
    try {
      var after = plan.assignments;
      if (code != null && (current?.includes(cell.personId) ?? false)) {
        after = RosterEditor.replace(
          after,
          day: cell.day,
          role: current!.nurseIds.contains(cell.personId)
              ? Role.nurse
              : Role.radiologyTech,
          oldId: cell.personId,
          newId: null,
          nursesPerDay: ref.read(effectiveSettingsProvider).nursesPerDay,
          secondary: current.isSecondaryTech(cell.personId),
        );
      }
      after = RosterEditor.setExtraShift(
        after,
        day: cell.day,
        personId: cell.personId,
        code: code,
      );
      await _apply(
        after,
        message: code == null
            ? '${_name(cell.personId)} ${formatDayMonth(cell.day, plan.month)} '
                  '${current?.extraShiftOf(cell.personId) ?? 'ek'} mesaisi '
                  'kaldırıldı.'
            : '${_name(cell.personId)} ${formatDayMonth(cell.day, plan.month)} '
                  '$code yazıldı.',
      );
    } on RosterEditException catch (e) {
      _notify(e.message);
    }
  }

  /// [day] gününde 7A var mı? Sorumlu hemşire tanımlıyken mesai günleri
  /// (hafta içi, tam gün tatil olmayan).
  bool _hasDayShiftSlot(int day) {
    final plan = _plan;
    final date = DateTime(plan.year, plan.month, day);
    if (date.weekday >= DateTime.saturday) return false;
    final fullHoliday = ref
        .read(holidaysProvider)
        .any(
          (h) =>
              !h.isHalfDay &&
              h.date.year == date.year &&
              h.date.month == date.month &&
              h.date.day == day,
        );
    if (fullHoliday) return false;
    return ref
        .read(peopleProvider)
        .any((p) => p.isChargeNurse && p.worksInMonth(plan.year, plan.month));
  }

  /// [id] kişisi [day] gününün 7A'sına yazılırsa uyarılar ([assignments]
  /// sonrasına göre): o gün nöbetçi, nöbet ertesi, izinli, istemediği gün.
  List<String> _dayShiftWarnings(
    String id,
    int day,
    Map<int, DayAssignment> assignments,
  ) {
    final plan = _plan;
    final tail = ref.read(monthPlanProvider.notifier).previousMonthTail();
    bool onDuty(int d) => d < 1
        ? tail.isNotEmpty && tail.last.contains(id)
        : assignments[d]?.includes(id) ?? false;
    // 16B ertesi çalışmaya engel değil; yalnız 24 nöbetin ertesi.
    bool afterHeavy(int d) =>
        onDuty(d) &&
        !(d >= 1 && (assignments[d]?.isSecondaryTech(id) ?? false));
    final who = '${_name(id)} ${formatDayMonth(day, plan.month)}';
    return [
      if (onDuty(day)) '$who nöbetçi.',
      if (afterHeavy(day - 1)) '$who nöbet ertesi.',
      if (ref.read(blockReasonsProvider)[id]?[day] case final reason?
          when reason != BlockReason.beforeAnnualLeave &&
              reason != BlockReason.afterAnnualLeave &&
              reason != BlockReason.beforeRadiationLeave &&
              reason != BlockReason.afterRadiationLeave)
        '$who: ${reason.label}.',
    ];
  }

  /// Hemşireyi [cell] gününün 7A'sına yazar; o gün 24 nöbetteyse nöbeti
  /// kalkar. O günün 7A'sı ondan alınıp bu kişiye verilir.
  Future<void> _writeDayShift(RosterCell cell) async {
    final plan = _plan;
    final day = cell.day;
    final id = cell.personId;
    var after = plan.assignments;
    final onShift = after[day]?.includes(id) ?? false;
    if (onShift) {
      after = RosterEditor.replace(
        after,
        day: day,
        role: Role.nurse,
        oldId: id,
        newId: null,
        nursesPerDay: ref.read(effectiveSettingsProvider).nursesPerDay,
      );
    }
    if (!await _confirmWarnings(_dayShiftWarnings(id, day, after))) return;
    await _apply(
      after,
      dayShiftOverrides: {...plan.dayShiftOverrides, day: id},
      message:
          '${_name(id)} ${formatDayMonth(day, plan.month)} '
          '${onShift ? '24 yerine ' : ''}7A\'ya yazıldı.',
    );
  }

  /// Teknikere [cell] gününde 7A yazar ([MonthPlan.techDayShifts]); o gün
  /// 24 / 16B nöbetindeyse nöbeti kalkar. Nöbet ertesi, izinli ya da
  /// istemediği günse önce uyarır.
  Future<void> _writeTechDayShift(RosterCell cell) async {
    final plan = _plan;
    final day = cell.day;
    final id = cell.personId;
    var after = plan.assignments;
    final current = after[day];
    final onShift = current?.includes(id) ?? false;
    if (onShift) {
      after = RosterEditor.replace(
        after,
        day: day,
        role: current!.nurseIds.contains(id) ? Role.nurse : Role.radiologyTech,
        oldId: id,
        newId: null,
        nursesPerDay: ref.read(effectiveSettingsProvider).nursesPerDay,
        secondary: current.isSecondaryTech(id),
      );
    }
    if (!await _confirmWarnings(_dayShiftWarnings(id, day, after))) return;
    await _apply(
      after,
      techDayShifts: {
        ...plan.techDayShifts,
        id: {...?plan.techDayShifts[id], day}.toList()..sort(),
      },
      message:
          '${_name(id)} ${formatDayMonth(day, plan.month)} '
          '${onShift ? 'nöbet yerine ' : ''}7A\'ya yazıldı.',
    );
  }

  /// Kişinin [cell] günündeki elle (ek) 7A'sını kaldırır.
  Future<void> _removeTechDayShift(RosterCell cell) async {
    final plan = _plan;
    final days = [
      for (final d in plan.techDayShifts[cell.personId] ?? const <int>[])
        if (d != cell.day) d,
    ];
    await _apply(
      plan.assignments,
      techDayShifts: {
        for (final e in plan.techDayShifts.entries)
          if (e.key != cell.personId) e.key: e.value,
        if (days.isNotEmpty) cell.personId: days,
      },
      message:
          '${_name(cell.personId)} ${formatDayMonth(cell.day, plan.month)} '
          '7A kaldırıldı.',
    );
  }

  /// Teknikeri [cell] gününde 16B (ya da [secondary] false ise 24)
  /// koltuğuna yazar; koltuktaki kişinin yerine geçer.
  Future<void> _writeTechSeat(
    RosterCell cell, {
    required bool secondary,
  }) async {
    final plan = _plan;
    final current = plan.assignments[cell.day];
    final replaced = secondary ? current?.tech16bId : current?.techId;
    final after = RosterEditor.setTechSeat(
      plan.assignments,
      day: cell.day,
      personId: cell.personId,
      secondary: secondary,
    );
    if (!await _confirmViolations(after)) return;
    await _apply(
      after,
      message:
          '${_name(cell.personId)} ${formatDayMonth(cell.day, plan.month)} '
          '${secondary ? "16B'ye" : "24'e"} yazıldı'
          '${replaced != null && replaced != cell.personId ? ' (${_name(replaced)} yerine)' : ''}.',
    );
  }

  /// Nöbetçi hemşirenin ya da 24'teki teknikerin [cell] günündeki
  /// vardiyasını 16A / 24 yapar.
  Future<void> _set16a(RosterCell cell, {required bool night}) async {
    final plan = _plan;
    try {
      final after = RosterEditor.set16a(
        plan.assignments,
        day: cell.day,
        personId: cell.personId,
        night: night,
      );
      await _apply(
        after,
        message:
            '${_name(cell.personId)} ${formatDayMonth(cell.day, plan.month)} '
            '${night ? "16A'ya" : "24'e"} çevrildi.',
      );
    } on RosterEditException catch (e) {
      _notify(e.message);
    }
  }

  /// Hemşireyi [cell] gününe 16A yazar: boş koltuk varsa oraya, yoksa
  /// seçilen hemşirenin yerine. Tekniker 24 koltuğuna (doluysa oradakinin
  /// yerine) 16A yazılır.
  Future<void> _write16a(RosterCell cell, Role role, {String? code}) async {
    final plan = _plan;
    // [code] verilirse 16A yerine o özel mesai yazılır.
    final label = code ?? '16A';
    Map<int, DayAssignment> mark(Map<int, DayAssignment> a) => code == null
        ? RosterEditor.set16a(
            a,
            day: cell.day,
            personId: cell.personId,
            night: true,
          )
        : RosterEditor.setCustomShift(
            a,
            day: cell.day,
            personId: cell.personId,
            code: code,
          );
    if (role == Role.radiologyTech) {
      final replaced = plan.assignments[cell.day]?.techId;
      try {
        final after = mark(
          RosterEditor.setTechSeat(
            plan.assignments,
            day: cell.day,
            personId: cell.personId,
            secondary: false,
          ),
        );
        if (!await _confirmViolations(after)) return;
        await _apply(
          after,
          message:
              '${_name(cell.personId)} ${formatDayMonth(cell.day, plan.month)} '
              '$label yazıldı'
              '${replaced == null || replaced == cell.personId ? '' : ' (${_name(replaced)} yerine)'}.',
        );
      } on RosterEditException catch (e) {
        _notify(e.message);
      }
      return;
    }
    final nursesPerDay = ref.read(effectiveSettingsProvider).nursesPerDay;
    final current = plan.assignments[cell.day] ?? DayAssignment(day: cell.day);
    String? replaced;
    if (current.nurseIds.length >= nursesPerDay) {
      replaced = await showDialog<String>(
        context: context,
        builder: (context) => SimpleDialog(
          title: Text('Kimin yerine $label?'),
          children: [
            for (final other in current.nurseIds)
              SimpleDialogOption(
                onPressed: () => Navigator.of(context).pop(other),
                child: Text(_name(other)),
              ),
          ],
        ),
      );
      if (replaced == null || !mounted) return;
    }
    try {
      var after = RosterEditor.replace(
        plan.assignments,
        day: cell.day,
        role: Role.nurse,
        oldId: replaced,
        newId: cell.personId,
        nursesPerDay: nursesPerDay,
      );
      after = mark(after);
      if (!await _confirmViolations(after)) return;
      await _apply(
        after,
        message:
            '${_name(cell.personId)} ${formatDayMonth(cell.day, plan.month)} '
            '$label yazıldı'
            '${replaced == null ? '' : ' (${_name(replaced)} yerine)'}.',
      );
    } on RosterEditException catch (e) {
      _notify(e.message);
    }
  }

  /// Uzun basma menüsü. Nöbet hücresinde: değiştir, sil, takas ve
  /// hemşirede 7A'ya / teknikerde 16B'ye (ya da 24'e) çevir. Boş hücrede:
  /// 24 nöbet yaz ve hemşirede 7A / teknikerde 16B yaz. 7A hücresinde
  /// dokunmayla aynı 7A seçenekleri açılır.
  Future<void> _onCellLongPress(RosterCell cell, Role role) async {
    if (_swapFrom != null) return _completeSwap(cell, role);
    if (!_ensureUnlocked()) return;
    final plan = _plan;
    final current = plan.assignments[cell.day];
    final onShift = current?.includes(cell.personId) ?? false;
    final secondary = current?.isSecondaryTech(cell.personId) ?? false;
    final night = current?.is16a(cell.personId) ?? false;
    final isDayShift =
        ref.read(dayShiftsProvider)[cell.day]?.personId == cell.personId;
    final nurse = role == Role.nurse;
    final tech = role == Role.radiologyTech;
    // Teknikerin elle 7A'sı (hücrede 7A yazar).
    final techHas7A = _techHas7A(cell, role);
    final can7A = _can7A(cell, role);
    final canExtra7A = _canExtra7A(cell, role);
    // Hemşirenin 7A hücresi dokunmayla aynı seçenekleri açar; boş
    // hemşire hücresinde 24 / 16A yaz seçilir.
    if (!onShift && isDayShift) return _onCellTap(cell, role);

    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(
                '${_name(cell.personId)} · ${_dayLabel(cell.day)}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            if (onShift) ...[
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Değiştir'),
                subtitle: const Text('Yerine başkasını yaz.'),
                onTap: () => Navigator.of(context).pop('edit'),
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('Sil'),
                subtitle: const Text('Nöbeti kaldır; koltuk boş kalır.'),
                onTap: () => Navigator.of(context).pop('delete'),
              ),
              if (can7A)
                ListTile(
                  leading: const Icon(Icons.wb_sunny_outlined),
                  title: const Text("7A'ya çevir"),
                  subtitle: Text(
                    nurse
                        ? '24 nöbeti kalkar, bu günün 7A\'sına yazılır.'
                        : 'Nöbeti kalkar, bu gün 7A (gündüz) çalışır.',
                  ),
                  onTap: () => Navigator.of(context).pop('7a'),
                ),
              if (canExtra7A)
                ListTile(
                  leading: const Icon(Icons.add_task),
                  title: const Text("Ek 7A'ya çevir"),
                  subtitle: const Text(
                    '24 nöbeti kalkar; sorumlunun 7A\'sına ek 7A çalışır.',
                  ),
                  onTap: () => Navigator.of(context).pop('extra7a'),
                ),
              if (nurse || (tech && !secondary))
                ListTile(
                  key: const ValueKey('nurse-16a-toggle'),
                  leading: const Icon(Icons.nights_stay_outlined),
                  title: Text(night ? "24'e çevir" : "16A'ya çevir"),
                  subtitle: Text(
                    night
                        ? '16A yerine 24 nöbet tutar.'
                        : '24 yerine 16A (16:00–08:00) tutar.',
                  ),
                  onTap: () =>
                      Navigator.of(context).pop(night ? 'n24' : 'n16a'),
                ),
              if (tech)
                ListTile(
                  leading: const Icon(Icons.schedule),
                  title: Text(secondary ? "24'e çevir" : "16B'ye çevir"),
                  subtitle: Text(
                    secondary
                        ? '16B yerine 24 nöbet tutar.'
                        : '24 yerine 16B vardiyası tutar.',
                  ),
                  onTap: () =>
                      Navigator.of(context).pop(secondary ? '24' : '16b'),
                ),
              ListTile(
                key: const ValueKey('swap-suggest'),
                leading: const Icon(Icons.auto_awesome),
                title: const Text('Takas önerileri'),
                subtitle: const Text('Kural bozmadan değişebileceği nöbetler.'),
                onTap: () => Navigator.of(context).pop('suggest'),
              ),
              ListTile(
                key: const ValueKey('why-shift'),
                leading: const Icon(Icons.help_outline),
                title: const Text('Neden bu nöbet?'),
                subtitle: const Text('Neden bu kişi, neden başkası değil.'),
                onTap: () => Navigator.of(context).pop('why'),
              ),
              ListTile(
                leading: const Icon(Icons.swap_horiz),
                title: const Text('Başka bir nöbetle takas et'),
                subtitle: const Text(
                  'Sonra takas edilecek ikinci nöbete dokunun.',
                ),
                onTap: () => Navigator.of(context).pop('swap'),
              ),
            ] else ...[
              if (techHas7A)
                ListTile(
                  leading: const Icon(Icons.wb_sunny_outlined),
                  title: const Text("7A'yı kaldır"),
                  onTap: () => Navigator.of(context).pop('no7a'),
                ),
              ListTile(
                leading: const Icon(Icons.add_circle_outline),
                title: const Text('24 nöbet yaz'),
                onTap: () => Navigator.of(context).pop('add'),
              ),
              if (can7A)
                ListTile(
                  leading: const Icon(Icons.wb_sunny_outlined),
                  title: const Text('7A yaz'),
                  subtitle: Text(
                    nurse
                        ? 'Bu günün 7A\'sı bu kişiye geçer.'
                        : 'Gündüz mesaisi, günün mesai saati kadar.',
                  ),
                  onTap: () => Navigator.of(context).pop('7a'),
                ),
              if (canExtra7A)
                ListTile(
                  key: const ValueKey('extra-7a-write'),
                  leading: const Icon(Icons.add_task),
                  title: const Text('Ek 7A yaz'),
                  subtitle: const Text(
                    'Sorumlunun 7A\'sı kalır; bu kişi de 7A çalışır.',
                  ),
                  onTap: () => Navigator.of(context).pop('extra7a'),
                ),
              ListTile(
                key: const ValueKey('nurse-16a-write'),
                leading: const Icon(Icons.nights_stay_outlined),
                title: const Text('16A yaz'),
                subtitle: Text(
                  nurse
                      ? '16:00–08:00; o günün bir hemşire koltuğunu doldurur.'
                      : '16:00–08:00; 24 koltuğunu doldurur, doluysa '
                            'oradakinin yerine.',
                ),
                onTap: () => Navigator.of(context).pop('n16a-new'),
              ),
              if (tech)
                ListTile(
                  leading: const Icon(Icons.schedule),
                  title: const Text('16B yaz'),
                  subtitle: const Text(
                    '16B koltuğunda başkası varsa onun yerine.',
                  ),
                  onTap: () => Navigator.of(context).pop('16b'),
                ),
            ],
          ],
        ),
      ),
    );
    if (!mounted) return;
    switch (choice) {
      case 'edit' || 'add':
        // Serbest düzenlemede "Değiştir" silmesin, seçenekleri açsın;
        // "24 nöbet yaz" ise her iki kipte de dokunmayla aynı.
        final free = _freeEdit;
        if (choice == 'edit') _freeEdit = false;
        try {
          await _onCellTap(cell, role);
        } finally {
          _freeEdit = free;
        }
      case 'delete':
        await _deleteShift(cell, role);
      case '7a':
        await (nurse ? _writeDayShift(cell) : _writeTechDayShift(cell));
      case 'no7a':
        await _removeTechDayShift(cell);
      case 'extra7a':
        await _writeTechDayShift(cell);
      case '16b':
        await _writeTechSeat(cell, secondary: true);
      case '24':
        await _writeTechSeat(cell, secondary: false);
      case 'n16a':
        await _set16a(cell, night: true);
      case 'n24':
        await _set16a(cell, night: false);
      case 'n16a-new':
        await _write16a(cell, role);
      case 'why':
        await _showWhy(cell);
      case 'suggest':
        await _showSwapSuggestions(cell);
      case 'swap':
        setState(() => _swapFrom = cell);
    }
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
      if (!await _confirmViolations(result)) return;
      await _apply(
        result,
        message:
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
    Iterable<DayShift> dayShifts, {
    required _ShareAction format,
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
    final fileBase =
        'nobet-${fileSlug(person.name)}-${plan.year}-'
        '${plan.month.toString().padLeft(2, '0')}';
    try {
      if (format == _ShareAction.addToCalendar) {
        await _addToCalendar(
          PersonalRoster.build(
            plan: plan,
            person: person,
            people: ref.read(peopleProvider),
            dayShifts: dayShifts,
          ),
          dayShifts,
        );
      } else if (format == _ShareAction.personalCalendar) {
        // Telefon takvimine eklenecek dosya (.ics).
        final ics = RosterCalendar.ics(
          data: PersonalRoster.build(
            plan: plan,
            person: person,
            people: ref.read(peopleProvider),
            dayShifts: dayShifts,
          ),
          dayShifts: dayShifts,
          customShifts: ref.read(rosterSettingsProvider).customShifts,
          now: ref.read(clockProvider)(),
        );
        await services.shareFile(
          utf8.encode(ics),
          '$fileBase.ics',
          RosterCalendar.mimeType,
        );
      } else if (format == _ShareAction.personalPdf) {
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
        await services.sharePdf(pdf, '$fileBase.pdf');
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

  /// Kişinin nöbetlerini ve 7A'larını doğrudan bu telefonun takvimine yazar
  /// (önceki akşam 20:00 hatırlatmalı). Aynı kişinin aynı ayı daha önce
  /// eklendiyse eski etkinlikler silinip güncelleri yazılır.
  Future<void> _addToCalendar(
    PersonalRosterData data,
    Iterable<DayShift> dayShifts,
  ) async {
    final events = RosterCalendar.events(
      data: data,
      dayShifts: dayShifts,
      customShifts: ref.read(rosterSettingsProvider).customShifts,
    );
    if (events.isEmpty) {
      _notify('${data.person.name}: bu ay takvime eklenecek nöbet yok.');
      return;
    }
    final calendar = ref.read(calendarServiceProvider);
    final access = await calendar.requestAccess();
    if (access == CalendarAccess.none) {
      _notify(
        'Takvim izni yok. Telefonun Ayarlar > Nöbetçi > Takvimler bölümünden '
        'izin verin.',
      );
      return;
    }
    final meta = ref.read(hiveBoxesProvider).meta;
    final key =
        'calendarEvents/${data.person.id}/${data.year}-'
        '${data.month.toString().padLeft(2, '0')}';
    final old = (meta.get(key) as List?)?.cast<String>() ?? const <String>[];
    if (access == CalendarAccess.full) {
      for (final id in old) {
        await calendar.delete(id);
      }
    }
    final ids = <String>[];
    try {
      for (final e in events) {
        ids.add(await calendar.add(e));
      }
    } catch (e) {
      if (mounted) _notify('Takvime eklenemedi: $e');
      return;
    } finally {
      await meta.put(key, [
        ...ids,
        // Silinemeyenler bir sonraki tam izinde silinsin.
        if (access != CalendarAccess.full) ...old,
      ]);
    }
    if (!mounted) return;
    final replaced = old.isNotEmpty && access == CalendarAccess.full;
    _notify(
      '${data.person.name}: ${ids.length} etkinlik takvime eklendi'
      '${replaced ? ' (eskiler güncellendi)' : ''}.',
    );
  }

  /// İdareye verilecek imza alanlı fazla çalışma çizelgesini paylaşır.
  /// Kurum / imza bilgileri Ayarlar > Rapor bilgileri'nden.
  Future<void> _shareOvertimeReport(
    MonthPlan plan,
    RosterSummary summary,
    int shiftHours,
  ) async {
    final services = ref.read(platformServicesProvider);
    try {
      final fonts = await services.loadPdfFonts();
      final pdf = await buildOvertimeReportPdf(
        year: plan.year,
        month: plan.month,
        summary: summary,
        info: ref.read(reportInfoProvider),
        shiftHours: shiftHours,
        font: fonts.regular,
        boldFont: fonts.bold,
        createdAt: ref.read(todayProvider),
      );
      await services.sharePdf(
        pdf,
        'fazla-mesai-${plan.year}-${plan.month.toString().padLeft(2, '0')}.pdf',
      );
    } catch (e) {
      if (mounted) _notify('Paylaşılamadı: $e');
    }
  }

  /// Herkesin kişiye özel PDF'ini ayrı dosyalar olarak tek seferde paylaşır.
  /// [calendar] ise PDF yerine herkesin takvim dosyası (.ics); ay içinde
  /// nöbeti ve 7A'sı olmayanlar atlanır.
  Future<void> _shareAllPersonal(
    List<RosterRow> rows,
    Iterable<DayShift> dayShifts, {
    required Set<int> weekendDays,
    required Set<int> holidayDays,
    bool calendar = false,
  }) async {
    final plan = _plan;
    final services = ref.read(platformServicesProvider);
    final people = ref.read(peopleProvider);
    final monthLabel = DateFormat.yMMMM(
      'tr_TR',
    ).format(DateTime(plan.year, plan.month));
    final month = plan.month.toString().padLeft(2, '0');
    try {
      final files = <({Uint8List bytes, String name, String mime})>[];
      if (calendar) {
        final now = ref.read(clockProvider)();
        for (final r in rows) {
          final person =
              _peopleById[r.id] ?? Person(id: r.id, name: r.name, role: r.role);
          final data = PersonalRoster.build(
            plan: plan,
            person: person,
            people: people,
            dayShifts: dayShifts,
          );
          if (data.shifts.isEmpty && data.dayShiftDays.isEmpty) continue;
          files.add((
            bytes: utf8.encode(
              RosterCalendar.ics(
                data: data,
                dayShifts: dayShifts,
                customShifts: ref.read(rosterSettingsProvider).customShifts,
                now: now,
              ),
            ),
            name: 'nobet-${fileSlug(person.name)}-${plan.year}-$month.ics',
            mime: RosterCalendar.mimeType,
          ));
        }
        if (files.isEmpty) {
          _notify('Takvime eklenecek nöbet yok.');
          return;
        }
        await services.shareFiles(
          files,
          subject: '$monthLabel nöbet takvimleri',
        );
        return;
      }
      final fonts = await services.loadPdfFonts();
      for (final r in rows) {
        final person =
            _peopleById[r.id] ?? Person(id: r.id, name: r.name, role: r.role);
        final pdf = await buildPersonalRosterPdf(
          data: PersonalRoster.build(
            plan: plan,
            person: person,
            people: people,
            dayShifts: dayShifts,
            weekendDays: weekendDays,
          ),
          weekendDays: weekendDays,
          holidayDays: holidayDays,
          font: fonts.regular,
          boldFont: fonts.bold,
          createdAt: ref.read(todayProvider),
        );
        files.add((
          bytes: pdf,
          name: 'nobet-${fileSlug(person.name)}-${plan.year}-$month.pdf',
          mime: 'application/pdf',
        ));
      }
      if (files.isEmpty) return;
      await services.shareFiles(
        files,
        subject: '$monthLabel kişiye özel nöbet listeleri',
      );
    } catch (e) {
      if (mounted) _notify('Paylaşılamadı: $e');
    }
  }

  /// Tüm listeyi paylaşırken ne gönderileceğini sorar: yalnız nöbet tablosu
  /// (false) ya da altında kişi başı özetle (true). Vazgeçilirse null.
  static const _columnsKey = 'shareSummaryColumns';

  /// Paylaşırken özet tablosunda hangi sütunlar olsun? Boş küme: yalnız
  /// liste; null: vazgeçildi. Seçim hatırlanır.
  Future<Set<SummaryColumn>?> _askDetails(_ShareAction action) async {
    final meta = ref.read(hiveBoxesProvider).meta;
    final saved = meta.get(_columnsKey);
    // Ücret sütunu yalnız ayarda saat ücreti girilmişse seçilebilir.
    final options = [
      for (final c in SummaryColumn.values)
        if (c != SummaryColumn.estimatedPay ||
            ShiftPay.enabled(ref.read(effectiveSettingsProvider)))
          c,
    ];
    final initial = saved is List
        ? SummaryColumn.fromNames(saved.cast<String>())
        : {...options};
    final picked = await showDialog<Set<SummaryColumn>>(
      context: context,
      builder: (_) => _ShareDetailsDialog(
        title: action == _ShareAction.print
            ? 'Ne yazdırılsın?'
            : 'Ne paylaşılsın?',
        initial: initial.intersection(options.toSet()),
        options: options,
      ),
    );
    if (picked != null && picked.isNotEmpty) {
      await meta.put(_columnsKey, [for (final c in picked) c.name]);
    }
    return picked;
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
    required Iterable<DayShift> dayShifts,
  }) async {
    final services = ref.read(platformServicesProvider);
    final fileBase =
        'nobet-listesi-${plan.year}-${plan.month.toString().padLeft(2, '0')}';
    final title =
        '${DateFormat.yMMMM('tr_TR').format(DateTime(plan.year, plan.month))} '
        'Nöbet Listesi';
    final columns = await _askDetails(action);
    if (columns == null || !mounted) return;
    final details = columns.isNotEmpty;
    try {
      if (action == _ShareAction.excel) {
        final xlsx = RosterExcel.build(
          plan: plan,
          rows: rows,
          summary: summary,
          weekendDays: weekendDays,
          holidayDays: holidayDays,
          shiftHours: shiftHours,
          missingByDay: missingByDay,
          dayShifts: dayShifts,
          includeSummary: details,
          summaryColumns: columns,
        );
        await services.shareFile(xlsx, '$fileBase.xlsx', XlsxWriter.mimeType);
        await markPublished(ref, plan);
        return;
      }
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
        includeSummary: details,
        summaryColumns: columns,
      );
      switch (action) {
        case _ShareAction.personal ||
            _ShareAction.personalPdf ||
            _ShareAction.personalCalendar ||
            _ShareAction.addToCalendar ||
            _ShareAction.overtimeReport ||
            _ShareAction.whatsAppEach ||
            _ShareAction.swapLog ||
            _ShareAction.notifyChanges ||
            _ShareAction.allPersonalPdf ||
            _ShareAction.allPersonalCalendar ||
            _ShareAction.excel:
          return;
        case _ShareAction.pdf:
          await services.sharePdf(pdf, '$fileBase.pdf');
        case _ShareAction.png:
          final png = await services.pdfToPng(pdf);
          await services.shareFile(png, '$fileBase.png', 'image/png');
        case _ShareAction.print:
          await services.printPdf(pdf, title);
      }
      // Herkese giden liste: sonraki değişiklikler buna göre bildirilir.
      await markPublished(ref, plan);
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
    final dayShifts = ref.watch(allDayShiftsProvider);
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
              _ShareAction.personalPdf ||
              _ShareAction.addToCalendar ||
              _ShareAction.personalCalendar => _sharePersonal(
                rows,
                dayShifts,
                format: action,
                weekendDays: weekendDays,
                holidayDays: holidayDays,
              ),
              _ShareAction.swapLog => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const SwapLogPage()),
              ),
              _ShareAction.notifyChanges => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const ChangeNoticePage(),
                ),
              ),
              _ShareAction.whatsAppEach => () async {
                await markPublished(ref, plan);
                if (!context.mounted) return;
                await Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => WhatsAppSendPage(
                      personIds: [for (final r in rows) r.id],
                      dayShifts: dayShifts,
                      weekendDays: weekendDays,
                      holidayDays: holidayDays,
                    ),
                  ),
                );
              }(),
              _ShareAction.overtimeReport => _shareOvertimeReport(
                plan,
                summary,
                settings.shiftHours,
              ),
              _ShareAction.allPersonalPdf ||
              _ShareAction.allPersonalCalendar => _shareAllPersonal(
                rows,
                dayShifts,
                weekendDays: weekendDays,
                holidayDays: holidayDays,
                calendar: action == _ShareAction.allPersonalCalendar,
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
                value: _ShareAction.excel,
                child: ListTile(
                  leading: Icon(Icons.table_view_outlined),
                  title: Text('Excel olarak paylaş'),
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
                value: _ShareAction.allPersonalPdf,
                child: ListTile(
                  leading: Icon(Icons.groups_outlined),
                  title: Text('Herkesin listesi (PDF)'),
                ),
              ),
              PopupMenuItem(
                value: _ShareAction.whatsAppEach,
                child: ListTile(
                  leading: Icon(Icons.send_to_mobile_outlined),
                  title: Text('Herkese WhatsApp\'tan gönder'),
                ),
              ),
              PopupMenuItem(
                value: _ShareAction.swapLog,
                child: ListTile(
                  leading: Icon(Icons.swap_horiz),
                  title: Text('Takas defteri'),
                ),
              ),
              PopupMenuItem(
                value: _ShareAction.notifyChanges,
                child: ListTile(
                  leading: Icon(Icons.campaign_outlined),
                  title: Text('Değişiklikleri bildir'),
                ),
              ),
              PopupMenuItem(
                value: _ShareAction.overtimeReport,
                child: ListTile(
                  leading: Icon(Icons.assignment_outlined),
                  title: Text('Fazla mesai raporu (PDF)'),
                ),
              ),
              PopupMenuItem(
                value: _ShareAction.personal,
                child: ListTile(
                  leading: Icon(Icons.person_outline),
                  title: Text('Kişiye özel liste (mesaj)'),
                ),
              ),
              PopupMenuItem(
                value: _ShareAction.addToCalendar,
                child: ListTile(
                  leading: Icon(Icons.edit_calendar_outlined),
                  title: Text('Bu telefonun takvimine ekle'),
                ),
              ),
              PopupMenuItem(
                value: _ShareAction.personalCalendar,
                child: ListTile(
                  leading: Icon(Icons.event_outlined),
                  title: Text('Takvim dosyası (kişiye özel)'),
                ),
              ),
              PopupMenuItem(
                value: _ShareAction.allPersonalCalendar,
                child: ListTile(
                  leading: Icon(Icons.calendar_month_outlined),
                  title: Text('Herkesin takvim dosyası'),
                ),
              ),
            ],
          ),
          IconButton(
            tooltip: 'Değişiklik geçmişi',
            icon: const Icon(Icons.history),
            onPressed: () {
              setState(() => _swapFrom = null);
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const RosterHistoryPage(),
                ),
              );
            },
          ),
          IconButton(
            tooltip: 'Listeyi sıfırla',
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed: _reset,
          ),
        ],
      ),
      // Bölümlü kaydırma: tablonun gün başlıkları aşağı kaydırırken üstte
      // sabit kalır.
      body: CustomScrollView(
        slivers: [
          SliverList.list(
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
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          FilterChip(
                            avatar: const Icon(
                              Icons.touch_app_outlined,
                              size: 18,
                            ),
                            label: const Text('Serbest düzenleme'),
                            selected: _freeEdit,
                            onSelected: (v) => setState(() => _freeEdit = v),
                          ),
                          ActionChip(
                            key: const ValueKey('text-edit'),
                            avatar: const Icon(
                              Icons.keyboard_outlined,
                              size: 18,
                            ),
                            label: const Text('Yazarak düzenle'),
                            onPressed: _textEdit,
                          ),
                          ActionChip(
                            key: const ValueKey('what-if'),
                            avatar: const Icon(
                              Icons.science_outlined,
                              size: 18,
                            ),
                            label: const Text('Ya şöyle olursa'),
                            onPressed: _whatIf,
                          ),
                          ActionChip(
                            key: const ValueKey('person-calendar'),
                            avatar: const Icon(
                              Icons.calendar_month_outlined,
                              size: 18,
                            ),
                            label: const Text('Kişi takvimi'),
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => PersonCalendarPage(
                                  initialPersonId: _highlightId,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _freeEdit
                            ? 'Serbest düzenleme açık: mesai günlerinde dokundukça '
                                  'boş → 24 → 7A → boş; hafta sonu ve tatilde nöbete '
                                  'dokununca silinir. Basılı tutunca 16A ve Ek 7A '
                                  'seçenekleri. Kurallar engellemez; ihlaller aşağıda '
                                  'uyarı olarak görünür.'
                            : 'Düzenlemek için hücreye dokunun ya da basılı tutun; '
                                  'basılı tutunca takas da seçilebilir.',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
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
              if (_highlightId case final id?)
                _HighlightSummary(
                  key: const ValueKey('highlight-summary'),
                  name: _name(id),
                  stats: _personStats(id, weekendDays, dayShifts),
                  onClose: () => setState(() => _highlightId = null),
                ),
            ],
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            sliver: RosterTable(
              plan: plan,
              rows: rows,
              personColors: {for (final p in people) p.id: PersonColors.of(p)},
              highlightedId: _highlightId,
              onNameTap: (id) =>
                  setState(() => _highlightId = _highlightId == id ? null : id),
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
              onCellLongPress: (cell) =>
                  _onCellLongPress(cell, roleById[cell.personId]!),
              onMissingTap: _onMissingTap,
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.only(bottom: 24),
            sliver: SliverList.list(
              children: [
                if (violations.isNotEmpty && !plan.isLocked)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: FilledButton.tonalIcon(
                        onPressed: _fixing ? null : _fixRoster,
                        icon: _fixing
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.auto_fix_high),
                        label: const Text('Kurallara göre düzelt'),
                      ),
                    ),
                  ),
                _ViolationList(
                  key: const ValueKey('violations'),
                  violations: violations,
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Text('Özet', style: theme.textTheme.titleMedium),
                ),
                SummaryTable(summary: summary),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Kural ihlalleri, önem sırasıyla ayrı kutularda: boş günler (en üstte),
/// izinli ya da istemediği günde çalışanlar ve (elle düzenlemeden doğan) diğer ihlaller.
/// Kural ihlalleri: kapalıyken uyarı işaretli bir düğme (sayıyla), basınca
/// türlerine göre kutular açılır.
class _ViolationList extends StatefulWidget {
  const _ViolationList({super.key, required this.violations});

  final List<RuleViolation> violations;

  @override
  State<_ViolationList> createState() => _ViolationListState();
}

class _ViolationListState extends State<_ViolationList> {
  var _open = false;

  @override
  Widget build(BuildContext context) {
    final violations = widget.violations;
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
    // Boş koltuk varsa kırmızı, yoksa turuncu uyarı.
    final color = missing.isNotEmpty ? scheme.error : warning;
    final toggle = Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          key: const ValueKey('violations-toggle'),
          style: OutlinedButton.styleFrom(
            foregroundColor: color,
            side: BorderSide(color: color),
          ),
          onPressed: () => setState(() => _open = !_open),
          icon: const Icon(Icons.warning_amber_rounded),
          label: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Kural ihlalleri (${violations.length})'),
              const SizedBox(width: 4),
              Icon(_open ? Icons.expand_less : Icons.expand_more, size: 20),
            ],
          ),
        ),
      ),
    );
    if (!_open) return toggle;
    return Column(
      children: [
        toggle,
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

enum _ShareAction {
  pdf,
  png,
  excel,
  print,
  personalPdf,
  allPersonalPdf,
  personal,
  addToCalendar,
  personalCalendar,
  allPersonalCalendar,
  overtimeReport,
  whatsAppEach,
  swapLog,
  notifyChanges,
}

/// Vurgulanan kişinin özeti: tablonun üstünde, kapatılabilir.
class _HighlightSummary extends StatelessWidget {
  const _HighlightSummary({
    super.key,
    required this.name,
    required this.stats,
    required this.onClose,
  });

  final String name;
  final List<String> stats;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      color: scheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                  Text(
                    stats.join(' · '),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Vurguyu kaldır',
              icon: Icon(Icons.close, color: scheme.onPrimaryContainer),
              onPressed: onClose,
            ),
          ],
        ),
      ),
    );
  }
}

/// Paylaşma seçimi: "Yalnız liste" ya da özet sütunlarını işaretleyip
/// "Liste ve seçilenler".
class _ShareDetailsDialog extends StatefulWidget {
  const _ShareDetailsDialog({
    required this.title,
    required this.initial,
    required this.options,
  });

  final String title;
  final Set<SummaryColumn> initial;

  /// Seçilebilir sütunlar.
  final List<SummaryColumn> options;

  @override
  State<_ShareDetailsDialog> createState() => _ShareDetailsDialogState();
}

class _ShareDetailsDialogState extends State<_ShareDetailsDialog> {
  late final _selected = {...widget.initial};

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(widget.title),
      contentPadding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Listenin altındaki kişi başı özette hangi sütunlar olsun? '
                'Ad ve görev her zaman yazılır. Seçimin hatırlanır.',
                style: theme.textTheme.bodySmall,
              ),
            ),
            for (final c in widget.options)
              CheckboxListTile(
                key: ValueKey('col-${c.name}'),
                dense: true,
                value: _selected.contains(c),
                title: Text(c.label),
                onChanged: (v) =>
                    setState(() => v! ? _selected.add(c) : _selected.remove(c)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('share-list-only'),
          onPressed: () => Navigator.of(context).pop(<SummaryColumn>{}),
          child: const Text('Yalnız liste'),
        ),
        FilledButton(
          key: const ValueKey('share-with-details'),
          onPressed: _selected.isEmpty
              ? null
              : () => Navigator.of(context).pop({..._selected}),
          child: const Text('Liste ve seçilenler'),
        ),
      ],
    );
  }
}
