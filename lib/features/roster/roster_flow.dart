import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../month/month_plan_controller.dart';

/// "Listeyi Oluştur" / "Yeniden oluştur" akışı: kilit onayı, uygunluk
/// uyarıları, ilerleme göstergesi ve eksik kalan günlerin raporu.
/// Liste oluşturulduysa true döner.
Future<bool> generateRoster(BuildContext context, WidgetRef ref) async {
  final plan = ref.read(monthPlanProvider);
  final controller = ref.read(monthPlanProvider.notifier);

  if (plan.isLocked) {
    final ok = await _confirm(
      context,
      title: 'Bu ay kilitli',
      message:
          'Kilitli listeyi yeniden oluşturursanız mevcut liste silinir. '
          'Devam edilsin mi?',
      confirmLabel: 'Yeniden oluştur',
    );
    if (!ok || !context.mounted) return false;
  }

  final report = ref.read(monthFeasibilityProvider);
  if (!report.isFeasible) {
    final ok = await _confirm(
      context,
      title: 'Uygunluk sorunları var',
      message:
          '${report.issues.map((i) => '• ${i.message}').join('\n')}\n\n'
          'Liste tam kurulamayabilir; eksik kalan günler raporlanır. '
          'Yine de denensin mi?',
      confirmLabel: 'Yine de dene',
    );
    if (!ok || !context.mounted) return false;
  }

  final navigator = Navigator.of(context);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 24),
            Expanded(child: Text('Liste oluşturuluyor…')),
          ],
        ),
      ),
    ),
  );
  final result = await controller.generate();
  navigator.pop();

  if (!result.isComplete && context.mounted) {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Liste tam kurulamadı'),
        content: SingleChildScrollView(
          child: Text(result.issues.map((i) => '• ${i.message}').join('\n')),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Tamam'),
          ),
        ],
      ),
    );
  }
  return true;
}

Future<bool> _confirm(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: SingleChildScrollView(child: Text(message)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Vazgeç'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}
