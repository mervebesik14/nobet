import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../logic/block_reason.dart';
import '../../logic/day_shift_planner.dart';
import '../../logic/file_names.dart';
import '../../logic/personal_roster.dart';
import '../../logic/roster_calendar.dart';
import '../../logic/roster_editor.dart';
import '../../logic/roster_excel.dart';
import '../../logic/roster_generator.dart';
import '../../logic/roster_summary.dart';
import '../../logic/roster_validator.dart';
import '../../logic/shift_gaps.dart';
import '../../logic/turkish_collation.dart';
import '../../logic/turkish_dates.dart';
import '../../logic/xlsx_writer.dart';
import '../../models/models.dart';
import '../holidays/holidays_controller.dart';
import '../month/month_plan_controller.dart';
import '../people/people_controller.dart';
import '../../shared/platform_services.dart';
import '../../shared/providers.dart';
import 'edit_sheet.dart';
import 'personal_roster_pdf.dart';
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
          content: Text(message),
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
    if (_freeEdit) return _toggleCell(cell, role);

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

  /// Teknikerin [cell] gününde elle 7A'sı var mı (o gün nöbette değilken)?
  bool _techHas7A(RosterCell cell, Role role) =>
      role == Role.radiologyTech &&
      !(_plan.assignments[cell.day]?.includes(cell.personId) ?? false) &&
      (_plan.techDayShifts[cell.personId]?.contains(cell.day) ?? false);

  /// [cell] kişisine o gün 7A yazılabilir mi? Hemşire: sorumlu hemşire
  /// tanımlıyken mesai günü ve o günün 7A'sı zaten onda değilse. Tekniker:
  /// mesai günü ve henüz 7A'sı yoksa.
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
    ];
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
        role: Role.radiologyTech,
        oldId: id,
        newId: null,
        nursesPerDay: ref.read(effectiveSettingsProvider).nursesPerDay,
        secondary: current!.isSecondaryTech(id),
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

  /// Teknikerin [cell] günündeki elle 7A'sını kaldırır.
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
    final isDayShift =
        ref.read(dayShiftsProvider)[cell.day]?.personId == cell.personId;
    final nurse = role == Role.nurse;
    final tech = role == Role.radiologyTech;
    // Teknikerin elle 7A'sı (hücrede 7A yazar).
    final techHas7A = _techHas7A(cell, role);
    final can7A = _can7A(cell, role);
    if (!onShift && (isDayShift || (nurse && !can7A))) {
      return _onCellTap(cell, role);
    }

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
      case '16b':
        await _writeTechSeat(cell, secondary: true);
      case '24':
        await _writeTechSeat(cell, secondary: false);
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
      if (format == _ShareAction.personalCalendar) {
        // Telefon takvimine eklenecek dosya (.ics).
        final ics = RosterCalendar.ics(
          data: PersonalRoster.build(
            plan: plan,
            person: person,
            people: ref.read(peopleProvider),
            dayShifts: dayShifts,
          ),
          dayShifts: dayShifts,
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

  /// Herkesin kişiye özel PDF'ini ayrı dosyalar olarak tek seferde paylaşır.
  Future<void> _shareAllPersonal(
    List<RosterRow> rows,
    Iterable<DayShift> dayShifts, {
    required Set<int> weekendDays,
    required Set<int> holidayDays,
  }) async {
    final plan = _plan;
    final services = ref.read(platformServicesProvider);
    final people = ref.read(peopleProvider);
    final monthLabel = DateFormat.yMMMM(
      'tr_TR',
    ).format(DateTime(plan.year, plan.month));
    final month = plan.month.toString().padLeft(2, '0');
    try {
      final fonts = await services.loadPdfFonts();
      final files = <({Uint8List bytes, String name, String mime})>[];
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
  Future<bool?> _askDetails(_ShareAction action) => showDialog<bool>(
    context: context,
    builder: (context) => SimpleDialog(
      title: Text(
        action == _ShareAction.print ? 'Ne yazdırılsın?' : 'Ne paylaşılsın?',
      ),
      children: [
        SimpleDialogOption(
          key: const ValueKey('share-list-only'),
          onPressed: () => Navigator.of(context).pop(false),
          child: const ListTile(
            leading: Icon(Icons.table_chart_outlined),
            title: Text('Yalnız liste'),
            subtitle: Text('Nöbet tablosu'),
          ),
        ),
        SimpleDialogOption(
          key: const ValueKey('share-with-details'),
          onPressed: () => Navigator.of(context).pop(true),
          child: const ListTile(
            leading: Icon(Icons.summarize_outlined),
            title: Text('Liste ve ayrıntılar'),
            subtitle: Text(
              'Altında kişi başı özet: nöbet, hafta sonu, saatler, '
              'fazla mesai',
            ),
          ),
        ),
      ],
    ),
  );

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
    final details = await _askDetails(action);
    if (details == null || !mounted) return;
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
        );
        await services.shareFile(xlsx, '$fileBase.xlsx', XlsxWriter.mimeType);
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
      );
      switch (action) {
        case _ShareAction.personal ||
            _ShareAction.personalPdf ||
            _ShareAction.personalCalendar ||
            _ShareAction.allPersonalPdf ||
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
              _ShareAction.personalCalendar => _sharePersonal(
                rows,
                dayShifts,
                format: action,
                weekendDays: weekendDays,
                holidayDays: holidayDays,
              ),
              _ShareAction.allPersonalPdf => _shareAllPersonal(
                rows,
                dayShifts,
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
                value: _ShareAction.personal,
                child: ListTile(
                  leading: Icon(Icons.person_outline),
                  title: Text('Kişiye özel liste (mesaj)'),
                ),
              ),
              PopupMenuItem(
                value: _ShareAction.personalCalendar,
                child: ListTile(
                  leading: Icon(Icons.event_outlined),
                  title: Text('Takvim dosyası (kişiye özel)'),
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
                      FilterChip(
                        avatar: const Icon(Icons.touch_app_outlined, size: 18),
                        label: const Text('Serbest düzenleme'),
                        selected: _freeEdit,
                        onSelected: (v) => setState(() => _freeEdit = v),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _freeEdit
                            ? 'Serbest düzenleme açık: boş hücreye dokununca kişi '
                                  'o güne yazılır, nöbete dokununca silinir. Kurallar '
                                  'engellemez; ihlaller aşağıda uyarı olarak görünür.'
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
  personalCalendar,
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
