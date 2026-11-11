import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../../logic/month_close.dart';
import '../../logic/turkish_dates.dart';
import '../../shared/widgets/brand_widgets.dart';
import '../../shared/widgets/motion.dart';
import '../month/month_plan_controller.dart';
import '../settings/backup_actions.dart';

/// Ay kapanış sihirbazı: kontrol, kilit, herkese gönderme, fazla mesai
/// raporu, kişisel PDF'ler ve yedek tek ekranda, sırayla. Yapılan adımlar
/// ay için hatırlanır.
class MonthClosePage extends ConsumerStatefulWidget {
  const MonthClosePage({
    super.key,
    required this.checkLines,
    required this.onPublish,
    required this.onOvertimeReport,
    required this.onPersonalPdfs,
  });

  /// Kontrol adımının satırları ([MonthClose.checkLines]).
  final List<String> checkLines;
  final Future<void> Function() onPublish;
  final Future<void> Function() onOvertimeReport;
  final Future<void> Function() onPersonalPdfs;

  @override
  ConsumerState<MonthClosePage> createState() => _MonthClosePageState();
}

class _MonthClosePageState extends ConsumerState<MonthClosePage> {
  CloseStep? _running;

  String get _key {
    final plan = ref.read(monthPlanProvider);
    return MonthClose.key(plan.year, plan.month);
  }

  Set<CloseStep> get _done {
    final raw = ref.read(hiveBoxesProvider).meta.get(_key);
    return raw is List ? MonthClose.fromNames(raw) : <CloseStep>{};
  }

  Future<void> _mark(CloseStep step) async {
    final done = {..._done, step};
    await ref.read(hiveBoxesProvider).meta.put(_key, [
      for (final s in done) s.name,
    ]);
    if (mounted) setState(() {});
  }

  bool get _hasIssues =>
      !(widget.checkLines.length == 1 &&
          widget.checkLines.single == 'Her şey yolunda.');

  Future<void> _run(CloseStep step) async {
    setState(() => _running = step);
    try {
      final ok = await switch (step) {
        CloseStep.check => _confirmCheck(),
        CloseStep.lock => () async {
          final plan = ref.read(monthPlanProvider);
          if (!plan.isLocked) {
            await ref.read(monthPlanProvider.notifier).setLocked(true);
          }
          return true;
        }(),
        CloseStep.publish => widget.onPublish().then((_) => true),
        CloseStep.overtime => widget.onOvertimeReport().then((_) => true),
        CloseStep.personal => widget.onPersonalPdfs().then((_) => true),
        CloseStep.backup => exportBackup(context, ref),
      };
      if (ok) await _mark(step);
    } finally {
      if (mounted) setState(() => _running = null);
    }
  }

  /// Sorun varsa sorulur; "Yine de devam" ile kontrol tamamlanır.
  Future<bool> _confirmCheck() async {
    if (!_hasIssues) return true;
    final go = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Listede bakılacak şeyler var'),
        content: Text(widget.checkLines.map((l) => '• $l').join('\n')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Listeye dön'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Yine de devam'),
          ),
        ],
      ),
    );
    if (go == false && mounted) Navigator.of(context).pop();
    return go ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final plan = ref.watch(monthPlanProvider);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final done = _done;
    final next = MonthClose.next(done);
    final total = CloseStep.values.length;

    return Scaffold(
      appBar: AppBar(
        title: Text('${turkishMonthNames[plan.month - 1]} · Ay kapanışı'),
      ),
      body: ListView(
        padding: const EdgeInsets.only(top: 12, bottom: 100),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  next == null
                      ? 'Ay kapandı. Hepsi tamam.'
                      : '${done.length} / $total adım tamam',
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                    value: done.length / total,
                    minHeight: 8,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          GroupCard(
            children: [
              for (final (i, s) in CloseStep.values.indexed)
                ListTile(
                  key: ValueKey('close-${s.name}'),
                  leading: done.contains(s)
                      ? const SuccessTick(size: 30)
                      : CircleAvatar(
                          radius: 15,
                          backgroundColor: s == next
                              ? scheme.primary
                              : scheme.surfaceContainerHigh,
                          foregroundColor: s == next
                              ? scheme.onPrimary
                              : scheme.onSurfaceVariant,
                          child: Text(
                            '${i + 1}',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                  title: Text(s.label),
                  subtitle: Text(
                    s == CloseStep.check
                        ? widget.checkLines.join('\n')
                        : s == CloseStep.lock && plan.isLocked
                        ? 'Liste kilitli.'
                        : s.description,
                    style: s == CloseStep.check && _hasIssues
                        ? TextStyle(color: scheme.error)
                        : null,
                  ),
                  trailing: TextButton(
                    onPressed: _running == null ? () => _run(s) : null,
                    child: Text(
                      _running == s
                          ? '…'
                          : done.contains(s)
                          ? 'Tekrar'
                          : 'Yap',
                    ),
                  ),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: Text(
              'Adımlar bu ay için hatırlanır; istediğin zaman kaldığın yerden '
              'devam edebilirsin.',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
      floatingActionButton: next == null
          ? null
          : FloatingActionButton.extended(
              key: const ValueKey('close-next'),
              heroTag: null,
              onPressed: _running == null ? () => _run(next) : null,
              icon: const Icon(Icons.play_arrow_rounded),
              label: Text('Sıradaki: ${next.label}'),
            ),
    );
  }
}
