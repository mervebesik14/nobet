import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../../logic/feasibility_checker.dart';
import '../people/people_controller.dart';
import '../month/month_plan_controller.dart';

/// "Listeyi Oluştur" / "Yeniden oluştur" akışı: önce mod seçimi (hemşire +
/// tekniker / yalnız hemşire), kilit onayı, uygunluk uyarıları, ilerleme
/// göstergesi ve eksik kalan günlerin raporu. Liste oluşturulduysa true döner.
Future<bool> generateRoster(BuildContext context, WidgetRef ref) async {
  final plan = ref.read(monthPlanProvider);
  final controller = ref.read(monthPlanProvider.notifier);
  final hasTechs = ref.read(rosterSettingsProvider).techsPerDay > 0;

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

  // Mod: yalnızca tekniker tanımlıysa sor; değilse zaten yalnız hemşire.
  final bool nurseOnly;
  if (hasTechs) {
    final choice = await _chooseMode(context);
    if (choice == null || !context.mounted) return false;
    nurseOnly = choice;
  } else {
    nurseOnly = true;
  }

  // Uygunluk, seçilen moda göre (yalnız hemşirede tekniker aranmaz).
  final report =
      FeasibilityChecker(
        effectiveSettings(
          ref.read(rosterSettingsProvider),
          nurseOnly: nurseOnly,
        ),
      ).check(
        year: plan.year,
        month: plan.month,
        people: ref.read(peopleProvider),
        // İstenmeyen günler + izinler + yıllık izin öncesi/sonrası kuralları.
        unavailableDays: ref.read(effectiveBlockedDaysProvider),
        requestedShifts: plan.requestedShifts,
      );
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
  final result = await controller.generate(nurseOnly: nurseOnly);
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

/// Liste kimler için oluşturulsun? true = yalnız hemşire, false = hemşire +
/// tekniker, null = vazgeçildi.
Future<bool?> _chooseMode(BuildContext context) {
  return showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Liste kimler için?'),
      content: const Text('Nöbet listesini kimler için oluşturalım?'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Vazgeç'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Yalnız hemşire'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Hemşire + Tekniker'),
        ),
      ],
    ),
  );
}

/// Seçili ayın oluşturulmuş listesini onayla sıfırlar. İstenmeyen günler,
/// izinler ve fazla mesai istekleri korunur. Liste kilitliyse kilit de
/// açılır (onay metninde söylenir). Sıfırlandıysa true döner.
Future<bool> resetRosterFlow(BuildContext context, WidgetRef ref) async {
  final plan = ref.read(monthPlanProvider);
  if (!plan.hasRoster) return false;
  final ok = await _confirm(
    context,
    title: 'Listeyi sıfırla',
    message:
        'Bu ayın oluşturulan nöbet listesi silinecek. İstenmeyen günler, '
        'izinler ve fazla mesai istekleri korunur.'
        '${plan.isLocked ? '\n\nListe kilitli; sıfırlanınca kilidi de açılır.' : ''}'
        '\n\nDevam edilsin mi?',
    confirmLabel: 'Sıfırla',
  );
  if (!ok) return false;
  final controller = ref.read(monthPlanProvider.notifier);
  if (plan.isLocked) await controller.setLocked(false);
  return controller.resetRoster();
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
