import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../models/models.dart';
import '../month/month_plan_controller.dart';

/// Seçili ayın nöbet listesi değişiklik geçmişi: elle değişiklikler, 7A
/// seçimleri, pasife alma, oluşturma ve sıfırlama. Her kayıt, o
/// değişiklikten önceki hâle dönülerek geri alınabilir.
class RosterHistoryPage extends ConsumerWidget {
  const RosterHistoryPage({super.key});

  /// Kayıtta en fazla gösterilen ayrıntı satırı.
  static const _maxLines = 6;

  Future<void> _undo(
    BuildContext context,
    WidgetRef ref,
    int index,
    int count,
  ) async {
    final later = count - 1 - index;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Geri alınsın mı?'),
        content: Text(
          later == 0
              ? 'Liste bu değişiklikten önceki hâline döner.'
              : 'Bu değişiklik ve sonraki $later değişiklik geri alınır; '
                    'liste bu değişiklikten önceki hâline döner.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Geri al'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final done = await ref.read(monthPlanProvider.notifier).undoTo(index);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            done ? 'Geri alındı.' : 'Liste kilitli; önce kilidi açın.',
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plan = ref.watch(monthPlanProvider);
    final edits = ref.watch(rosterHistoryProvider);
    final theme = Theme.of(context);
    final time = DateFormat('d MMMM HH:mm', 'tr_TR');
    final month = DateFormat.yMMMM(
      'tr_TR',
    ).format(DateTime(plan.year, plan.month));

    return Scaffold(
      appBar: AppBar(title: Text('Değişiklik geçmişi · $month')),
      body: edits.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Bu ay için değişiklik kaydı yok.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                if (plan.isLocked)
                  const ListTile(
                    leading: Icon(Icons.lock),
                    title: Text('Liste kilitli; geri almak için kilidi açın.'),
                  ),
                // En yeni üstte.
                for (var i = edits.length - 1; i >= 0; i--)
                  _EditCard(
                    key: ValueKey('edit-$i'),
                    edit: edits[i],
                    time: time.format(edits[i].at),
                    maxLines: _maxLines,
                    theme: theme,
                    onUndo: plan.isLocked
                        ? null
                        : () => _undo(context, ref, i, edits.length),
                  ),
              ],
            ),
    );
  }
}

class _EditCard extends StatelessWidget {
  const _EditCard({
    super.key,
    required this.edit,
    required this.time,
    required this.maxLines,
    required this.theme,
    required this.onUndo,
  });

  final RosterEdit edit;
  final String time;
  final int maxLines;
  final ThemeData theme;
  final VoidCallback? onUndo;

  @override
  Widget build(BuildContext context) {
    final shown = edit.lines.take(maxLines).toList();
    final hidden = edit.lines.length - shown.length;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(edit.title, style: theme.textTheme.titleSmall),
                      Text(time, style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
                TextButton.icon(
                  onPressed: onUndo,
                  icon: const Icon(Icons.undo),
                  label: const Text('Geri al'),
                ),
              ],
            ),
            for (final line in shown)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text('• $line', style: theme.textTheme.bodyMedium),
              ),
            if (hidden > 0)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  've $hidden değişiklik daha',
                  style: theme.textTheme.bodySmall,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
