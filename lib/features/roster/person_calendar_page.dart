import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../logic/day_shift_planner.dart';
import '../../logic/roster_generator.dart';
import '../../logic/text_edits.dart';
import '../../logic/turkish_collation.dart';
import '../../logic/turkish_dates.dart';
import '../../models/models.dart';
import '../../shared/app_colors.dart';
import '../../shared/person_colors.dart';
import '../../shared/widgets/motion.dart';
import '../holidays/holidays_controller.dart';
import '../month/month_plan_controller.dart';
import '../people/people_controller.dart';

/// Kişi takvimi: bir kişi seçilir, ayın takviminde günlere dokunarak
/// nöbeti girilir. Dokundukça boş → 24 → (mesai gününde) 7A → boş;
/// basılı tutunca 16A, 16B, özel mesai ve sil seçenekleri.
class PersonCalendarPage extends ConsumerStatefulWidget {
  const PersonCalendarPage({super.key, this.initialPersonId});

  final String? initialPersonId;

  @override
  ConsumerState<PersonCalendarPage> createState() => _PersonCalendarPageState();
}

class _PersonCalendarPageState extends ConsumerState<PersonCalendarPage> {
  late String? _personId = widget.initialPersonId;

  List<Person> _people(MonthPlan plan) =>
      [
        for (final p in ref.read(peopleProvider))
          if (p.worksInMonth(plan.year, plan.month) &&
              (!plan.nurseOnly || p.role == Role.nurse))
            p,
      ]..sort((a, b) {
        final r = a.role.index.compareTo(b.role.index);
        return r != 0 ? r : compareTurkish(a.name, b.name);
      });

  bool _isWorkday(MonthPlan plan, int day) =>
      DayShiftPlanner.workdayHours(
        year: plan.year,
        month: plan.month,
        day: day,
        holidays: ref.read(holidaysProvider),
        settings: ref.read(effectiveSettingsProvider),
      ) !=
      null;

  /// Kişinin o günkü kodu: "24", "16A", "7A", özel mesai…; yoksa null.
  String? _code(MonthPlan plan, Person p, int day) {
    final a = plan.assignments[day];
    if (a != null && a.includes(p.id)) return a.shiftCode(p.id);
    if (a?.extraShiftOf(p.id) case final code?) return code;
    if (plan.techDayShifts[p.id]?.contains(day) ?? false) return '7A';
    return null;
  }

  Future<void> _run(List<TextEdit> edits) async {
    final plan = ref.read(monthPlanProvider);
    if (plan.isLocked) {
      _notify('Liste kilitli; düzenlemek için kilidi açın.');
      return;
    }
    final r = TextEdits.apply(
      plan: plan,
      edits: edits,
      settings: ref.read(effectiveSettingsProvider),
      holidays: ref.read(holidaysProvider),
    );
    if (r.errors.isNotEmpty) {
      _notify(r.errors.first.split(': ').last);
      return;
    }
    await ref
        .read(monthPlanProvider.notifier)
        .setAssignments(
          r.assignments,
          techDayShifts: r.techDayShifts,
          title: 'Kişi takviminden düzenleme',
        );
  }

  void _notify(String message) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));

  /// Dokununca: boş → 24 → (mesai günü, sorumlu değil) 7A → boş.
  Future<void> _tap(MonthPlan plan, Person p, int day) async {
    final code = _code(plan, p, day);
    final seat = plan.assignments[day]?.includes(p.id) ?? false;
    if (code == null) {
      final a = plan.assignments[day];
      final settings = ref.read(effectiveSettingsProvider);
      final occupants = p.role == Role.nurse ? [...?a?.nurseIds] : [?a?.techId];
      final full = p.role == Role.nurse
          ? occupants.length >= settings.nursesPerDay
          : occupants.isNotEmpty;
      if (!full) {
        await _run([
          TextEdit.write(p, [day], '24'),
        ]);
        return;
      }
      // Koltuk dolu: kimin yerine yazılacağı sorulur.
      final byId = {for (final x in ref.read(peopleProvider)) x.id: x};
      final old = await showDialog<Person>(
        context: context,
        builder: (context) => SimpleDialog(
          title: Text(
            '${formatDayMonth(day, plan.month)} dolu · kimin yerine?',
          ),
          children: [
            for (final id in occupants)
              if (byId[id] case final o?)
                SimpleDialogOption(
                  key: ValueKey('instead-$id'),
                  onPressed: () => Navigator.of(context).pop(o),
                  child: Row(
                    children: [
                      PersonAvatar.of(o, radius: 14),
                      const SizedBox(width: 10),
                      Text(o.name),
                    ],
                  ),
                ),
          ],
        ),
      );
      if (old == null || !mounted) return;
      await _run([TextEdit.replace(old, day, p)]);
    } else if (seat && _isWorkday(plan, day) && !p.isChargeNurse) {
      await _run([
        TextEdit.write(p, [day], '7A'),
      ]);
    } else {
      await _run([
        TextEdit.remove(p, [day]),
      ]);
    }
  }

  Future<void> _longPress(MonthPlan plan, Person p, int day) async {
    final settings = ref.read(effectiveSettingsProvider);
    final codes = [
      '24',
      '16A',
      if (p.role == Role.radiologyTech && settings.techsPerDay >= 2) '16B',
      if (_isWorkday(plan, day)) '7A',
      for (final c in settings.customShifts) c.code,
    ];
    final current = _code(plan, p, day);
    final scheme = Theme.of(context).colorScheme;
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${p.name} · '
                '${formatDayMonthWeekday(plan.year, plan.month, day)}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final c in codes)
                    ChoiceChip(
                      key: ValueKey('pick-$c'),
                      label: Text(c),
                      selected: current == c,
                      labelStyle: TextStyle(
                        color: current == c ? Colors.white : null,
                        fontWeight: FontWeight.w700,
                      ),
                      selectedColor: scheme.shiftColor(c),
                      onSelected: (_) => Navigator.of(context).pop(c),
                    ),
                  if (current != null)
                    ActionChip(
                      key: const ValueKey('pick-remove'),
                      avatar: const Icon(Icons.delete_outline, size: 18),
                      label: const Text('Sil'),
                      onPressed: () => Navigator.of(context).pop(''),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (choice == null || !mounted) return;
    await _run([
      if (choice.isEmpty)
        TextEdit.remove(p, [day])
      else ...[
        if (current != null && current != choice) TextEdit.remove(p, [day]),
        TextEdit.write(p, [day], choice),
      ],
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final plan = ref.watch(monthPlanProvider);
    ref.watch(peopleProvider);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final people = _people(plan);
    final person = people.where((p) => p.id == _personId).firstOrNull;
    final settings = ref.watch(effectiveSettingsProvider);
    final weekend = RosterGenerator.weekendDays(
      plan.year,
      plan.month,
      ref.watch(holidaysProvider),
      settings,
    );
    final blocked = ref.watch(blockReasonsProvider);
    final autoDayShifts = {
      for (final s in ref.watch(allDayShiftsProvider))
        if (s.personId == person?.id) s.day,
    };
    final offset = DateTime(plan.year, plan.month).weekday - 1;
    const weekdays = ['Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz'];

    int seatsTaken(int d) {
      final a = plan.assignments[d];
      if (a == null || person == null) return 0;
      return person.role == Role.nurse
          ? a.nurseIds.length
          : [?a.techId, ?a.tech16bId].length;
    }

    final seatsPerDay = person?.role == Role.radiologyTech
        ? settings.techsPerDay
        : settings.nursesPerDay;
    final shifts = person == null
        ? 0
        : plan.assignments.values.where((a) => a.includes(person.id)).length;
    final weekendShifts = person == null
        ? 0
        : plan.assignments.values
              .where((a) => a.includes(person.id) && weekend.contains(a.day))
              .length;

    return Scaffold(
      appBar: AppBar(
        title: Text('${turkishMonthNames[plan.month - 1]} · Kişi takvimi'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          SizedBox(
            height: 74,
            child: ListView(
              key: const ValueKey('person-strip'),
              scrollDirection: Axis.horizontal,
              children: [
                for (final p in people)
                  Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: GestureDetector(
                      key: ValueKey('pick-person-${p.id}'),
                      onTap: () => setState(() => _personId = p.id),
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                width: 2.5,
                                color: p.id == _personId
                                    ? scheme.primary
                                    : Colors.transparent,
                              ),
                            ),
                            child: PersonAvatar.of(p, radius: 20),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            p.name.split(' ').first,
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontWeight: p.id == _personId
                                  ? FontWeight.w800
                                  : null,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (person == null)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Yukarıdan bir kişi seçin; sonra takvimde günlere dokunarak '
                'nöbetini girin.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
            )
          else ...[
            Text(
              '${person.name} · $shifts nöbet · $weekendShifts hafta sonu',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'Dokundukça: boş → 24 → (hafta içi) 7A → boş. Basılı tutunca '
              '16A, özel mesai ve sil. Günün altındaki sayı o günün dolu '
              'koltukları.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                for (final w in weekdays)
                  Expanded(
                    child: Center(
                      child: Text(w, style: theme.textTheme.labelSmall),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            GridView.count(
              crossAxisCount: 7,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
              childAspectRatio: 0.78,
              children: [
                for (var i = 0; i < offset; i++) const SizedBox.shrink(),
                for (var d = 1; d <= plan.daysInMonth; d++)
                  () {
                    final code =
                        _code(plan, person, d) ??
                        (autoDayShifts.contains(d) ? '7A' : null);
                    final reason = blocked[person.id]?[d];
                    final leave = [
                      for (final t in LeaveType.values)
                        if (plan.leaveOf(person.id, t).contains(d)) t,
                    ].firstOrNull;
                    final taken = seatsTaken(d);
                    return Pressable(
                      key: ValueKey('pcal-$d'),
                      onTap: () => _tap(plan, person, d),
                      onLongPress: () => _longPress(plan, person, d),
                      child: Container(
                        decoration: BoxDecoration(
                          color: leave != null
                              ? scheme.leaveBackground(leave)
                              : weekend.contains(d)
                              ? scheme.weekendTint
                              : scheme.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(12),
                          border:
                              reason != null && (leave == null || code != null)
                              ? Border.all(color: scheme.error, width: 1.5)
                              : null,
                        ),
                        padding: const EdgeInsets.all(4),
                        child: Column(
                          children: [
                            Text(
                              '$d',
                              style: theme.textTheme.labelMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const Spacer(),
                            if (code != null)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 5,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: scheme.shiftColor(code),
                                  borderRadius: BorderRadius.circular(7),
                                ),
                                child: FittedBox(
                                  child: Text(
                                    code,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              )
                            else if (leave != null)
                              Text(
                                leave.shortLabel,
                                style: TextStyle(
                                  color: scheme.leaveInk(leave),
                                  fontWeight: FontWeight.w700,
                                  fontSize: 11,
                                ),
                              ),
                            const Spacer(),
                            Text(
                              '$taken/$seatsPerDay',
                              style: theme.textTheme.labelSmall?.copyWith(
                                fontSize: 9,
                                color: taken >= seatsPerDay
                                    ? scheme.onSurfaceVariant
                                    : scheme.error,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }(),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Kırmızı çerçeve: kişinin istemediği gün ya da kural engeli.',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}
