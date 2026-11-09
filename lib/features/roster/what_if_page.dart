import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../logic/roster_diff.dart';
import '../../logic/roster_generator.dart';
import '../../logic/turkish_collation.dart';
import '../../logic/turkish_dates.dart';
import '../../logic/what_if_report.dart';
import '../../models/models.dart';
import '../holidays/holidays_controller.dart';
import '../month/month_plan_controller.dart';
import '../people/people_controller.dart';

/// "Ya şöyle olursa": bir kişi birkaç gün izinli / gelemez olsaydı liste
/// en az değişiklikle nasıl olurdu; kaydetmeden gösterilir, istenirse
/// uygulanır.
class WhatIfPage extends ConsumerStatefulWidget {
  const WhatIfPage({super.key});

  @override
  ConsumerState<WhatIfPage> createState() => _WhatIfPageState();
}

/// Deneme türü: izin türleri ya da "istemiyor".
enum _Kind {
  annual('Yıllık izin', LeaveType.annual),
  sick('Rapor', LeaveType.sick),
  radiation('Şua', LeaveType.radiation),
  unavailable('Gelemez', null);

  const _Kind(this.label, this.type);
  final String label;
  final LeaveType? type;
}

class _WhatIfPageState extends ConsumerState<WhatIfPage> {
  String? _personId;
  _Kind _kind = _Kind.annual;
  int _start = 1;
  int _end = 1;
  bool _busy = false;
  ({MonthPlan plan, RosterResult result})? _preview;

  String get _title {
    final plan = ref.read(monthPlanProvider);
    final name = ref
        .read(peopleProvider)
        .firstWhere((p) => p.id == _personId)
        .name;
    final days = _start == _end
        ? formatDayMonth(_start, plan.month)
        : '$_start–${formatDayMonth(_end, plan.month)}';
    return 'Deneme: $name $days ${_kind.label.toLowerCase()}';
  }

  Future<void> _try() async {
    if (_personId == null) return;
    setState(() {
      _busy = true;
      _preview = null;
    });
    final lo = _start < _end ? _start : _end,
        hi = _start < _end ? _end : _start;
    final r = await ref.read(monthPlanProvider.notifier).previewAbsence(
      _personId!,
      _kind.type,
      [for (var d = lo; d <= hi; d++) d],
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _preview = r;
    });
  }

  Future<void> _apply() async {
    final p = _preview;
    if (p == null) return;
    final ok = await ref
        .read(monthPlanProvider.notifier)
        .applyPreview(p.plan, title: _title);
    if (!mounted) return;
    Navigator.of(context).pop(ok ? '$_title uygulandı.' : null);
  }

  @override
  Widget build(BuildContext context) {
    final plan = ref.watch(monthPlanProvider);
    final theme = Theme.of(context);
    final people = [
      for (final p in ref.watch(peopleProvider))
        if (p.worksInMonth(plan.year, plan.month) &&
            (!plan.nurseOnly || p.role == Role.nurse))
          p,
    ]..sort((a, b) => compareTurkish(a.name, b.name));
    final names = {for (final p in ref.watch(peopleProvider)) p.id: p.name};
    final preview = _preview;
    final report = preview == null
        ? null
        : WhatIfReport.compare(
            before: plan.assignments,
            after: preview.plan.assignments,
            people: ref.read(peopleProvider),
            weekendDays: RosterGenerator.weekendDays(
              plan.year,
              plan.month,
              ref.read(holidaysProvider),
              ref.read(effectiveSettingsProvider),
            ),
          );
    final lines = preview == null
        ? const <String>[]
        : RosterDiff.describe(
            month: plan.month,
            before: plan.assignments,
            after: preview.plan.assignments,
            name: (id) => names[id] ?? 'Silinmiş kişi',
          );
    final days = [for (var d = 1; d <= plan.daysInMonth; d++) d];

    return Scaffold(
      appBar: AppBar(title: const Text('Ya şöyle olursa')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: [
          Text(
            'Bir kişi birkaç gün gelemeseydi liste en az değişiklikle nasıl '
            'olurdu? Hiçbir şey kaydedilmez; beğenirsen uygularsın.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            key: const ValueKey('what-if-person'),
            initialValue: _personId,
            decoration: const InputDecoration(
              labelText: 'Kişi',
              border: OutlineInputBorder(),
            ),
            items: [
              for (final p in people)
                DropdownMenuItem(value: p.id, child: Text(p.name)),
            ],
            onChanged: (v) => setState(() {
              _personId = v;
              _preview = null;
            }),
          ),
          const SizedBox(height: 12),
          SegmentedButton<_Kind>(
            segments: [
              for (final k in _Kind.values)
                ButtonSegment(value: k, label: Text(k.label)),
            ],
            selected: {_kind},
            onSelectionChanged: (v) => setState(() {
              _kind = v.single;
              _preview = null;
            }),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<int>(
                  key: const ValueKey('what-if-start'),
                  initialValue: _start,
                  decoration: const InputDecoration(
                    labelText: 'İlk gün',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final d in days)
                      DropdownMenuItem(value: d, child: Text('$d')),
                  ],
                  onChanged: (v) => setState(() {
                    _start = v!;
                    if (_end < _start) _end = _start;
                    _preview = null;
                  }),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<int>(
                  key: ValueKey('what-if-end-$_end'),
                  initialValue: _end,
                  decoration: const InputDecoration(
                    labelText: 'Son gün',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final d in days)
                      DropdownMenuItem(value: d, child: Text('$d')),
                  ],
                  onChanged: (v) => setState(() {
                    _end = v!;
                    _preview = null;
                  }),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            key: const ValueKey('what-if-try'),
            onPressed: _personId == null || _busy ? null : _try,
            icon: _busy
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.science_outlined),
            label: const Text('Dene'),
          ),
          if (preview != null && report != null) ...[
            const Divider(height: 32),
            Text(
              report.changedSeats == 0
                  ? 'Liste değişmeden olur.'
                  : '${report.changedSeats} nöbet değişir.',
              style: theme.textTheme.titleMedium,
            ),
            if (preview.result.issues.isNotEmpty) ...[
              const SizedBox(height: 8),
              for (final i in preview.result.issues)
                Text(
                  '⚠ ${i.message}',
                  style: TextStyle(color: theme.colorScheme.error),
                ),
            ],
            if (report.loads.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('Yükü değişenler', style: theme.textTheme.titleSmall),
              for (final l in report.loads)
                Text('• ${WhatIfReport.describe(l)}'),
            ],
            if (lines.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('Değişiklikler', style: theme.textTheme.titleSmall),
              for (final l in lines) Text('• $l'),
            ],
          ],
        ],
      ),
      floatingActionButton: preview == null
          ? null
          : FloatingActionButton.extended(
              key: const ValueKey('what-if-apply'),
              heroTag: null,
              onPressed: _apply,
              icon: const Icon(Icons.check),
              label: const Text('Uygula'),
            ),
    );
  }
}
