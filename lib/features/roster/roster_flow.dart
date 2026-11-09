import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../../logic/feasibility_checker.dart';
import '../../logic/manual_edits.dart';
import '../../logic/roster_generator.dart';
import '../../logic/roster_options.dart';
import '../../shared/widgets/motion.dart';
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

  // Elle yapılanlar yeniden oluşturmada silinir: önce sor, düzeltmeyi öner.
  if (plan.hasRoster) {
    final manual = ManualEdits.since(
      ref.read(rosterHistoryRepositoryProvider).load(plan.year, plan.month),
    );
    if (!manual.isEmpty) {
      final choice = await _confirmManualEdits(
        context,
        manual,
        canFix: !plan.isLocked,
      );
      if (!context.mounted) return false;
      switch (choice) {
        case _Regenerate.cancel:
          return false;
        case _Regenerate.fix:
          final outcome = await controller.fixRoster();
          if (context.mounted && outcome != null) {
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(
                SnackBar(
                  content: Text(
                    outcome.changed == 0
                        ? 'Değiştirilecek nöbet bulunamadı; elle yapılanlar '
                              'korundu.'
                        : '${outcome.changed} nöbet değişti; elle yapılanlar '
                              'korundu.',
                  ),
                ),
              );
          }
          return false;
        case _Regenerate.regenerate:
          break;
      }
    }
  }
  if (!context.mounted) return false;

  // Mod: yalnızca tekniker tanımlıysa sor; değilse zaten yalnız hemşire.
  final bool nurseOnly;
  if (hasTechs) {
    final choice = await chooseRosterMode(context);
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
    builder: (_) => const PopScope(canPop: false, child: GeneratingDialog()),
  );
  final count = ref.read(rosterOptionCountProvider);
  final RosterResult result;
  if (count <= 1) {
    result = await controller.generate(nurseOnly: nurseOnly);
    navigator.pop();
  } else {
    final options = await controller.generateOptions(
      count: count,
      nurseOnly: nurseOnly,
    );
    navigator.pop();
    if (!context.mounted) return false;
    final picked = await chooseRosterOption(context, options);
    if (picked == null || !context.mounted) return false;
    result = picked;
    await controller.applyResult(result, nurseOnly: nurseOnly);
  }

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

/// Aday listeleri yan yana gösterir; seçilen döner (vazgeçilirse null).
/// En iyi aday "Önerilen" işaretlidir; her ölçüde en iyi değer kalın.
Future<RosterResult?> chooseRosterOption(
  BuildContext context,
  List<({RosterResult result, RosterOptionStats stats})> options,
) {
  final stats = [for (final o in options) o.stats];
  final best = RosterOptionStats.best(stats);
  final rows = <(String, int Function(RosterOptionStats))>[
    ('Eksik koltuk', (s) => s.missing),
    ('Toplam nöbet farkı', (s) => s.shiftSpread),
    ('Hafta sonu farkı', (s) => s.weekendSpread),
    ('Gün aşırı çift', (s) => s.everyOtherDayPairs),
    ('4–5 gün ara', (s) => s.longGaps),
  ];
  return showDialog<RosterResult>(
    context: context,
    builder: (context) {
      final theme = Theme.of(context);
      return AlertDialog(
        title: Text('${options.length} liste hazır'),
        contentPadding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Farklar rol grubu içinde en çok ile en az tutan arasındadır; '
                'hepsinde küçük olan daha iyi.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              Table(
                defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                columnWidths: const {0: FlexColumnWidth(2.2)},
                children: [
                  TableRow(
                    children: [
                      const SizedBox(),
                      for (var i = 0; i < options.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Column(
                            children: [
                              Text(
                                String.fromCharCode(65 + i),
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              if (i == best)
                                Text(
                                  'Önerilen',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: theme.colorScheme.primary,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  for (final (label, value) in rows)
                    TableRow(
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Text(label, style: theme.textTheme.bodySmall),
                        ),
                        for (final s in stats)
                          Text(
                            '${value(s)}',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight:
                                  value(s) == stats.map(value).reduce(min)
                                  ? FontWeight.w800
                                  : FontWeight.w400,
                            ),
                          ),
                      ],
                    ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Vazgeç'),
          ),
          for (var i = 0; i < options.length; i++)
            (i == best ? FilledButton.new : TextButton.new)(
              key: ValueKey('roster-option-$i'),
              onPressed: () => Navigator.of(context).pop(options[i].result),
              child: Text(String.fromCharCode(65 + i)),
            ),
        ],
      );
    },
  );
}

/// Liste kimler için oluşturulsun? true = yalnız hemşire, false = hemşire +
/// tekniker, null = vazgeçildi.
/// "Liste kimler için?": true = yalnız hemşire, false = hemşire + tekniker,
/// null = vazgeçildi.
Future<bool?> chooseRosterMode(BuildContext context) {
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

/// Seçili ayın oluşturulmuş listesini onayla sıfırlar. İzinler (yıllık,
/// şua, rapor) her zaman korunur. Kişi istekleri (istenmeyen günler,
/// sorumlu hemşirenin nöbet günleri, fazla mesai) varsa ayrıca sorulur:
/// korunabilir ya da birlikte sıfırlanabilir. Liste kilitliyse kilit de
/// açılır (onay metninde söylenir). Sıfırlandıysa true döner.
Future<bool> resetRosterFlow(BuildContext context, WidgetRef ref) async {
  final plan = ref.read(monthPlanProvider);
  if (!plan.hasRoster) return false;
  final ok = await _confirm(
    context,
    title: 'Listeyi sıfırla',
    message:
        'Bu ayın oluşturulan nöbet listesi silinecek. İzinler (yıllık izin, '
        'şua izni, rapor) korunur.'
        '${plan.isLocked ? '\n\nListe kilitli; sıfırlanınca kilidi de açılır.' : ''}'
        '\n\nDevam edilsin mi?',
    confirmLabel: 'Sıfırla',
  );
  if (!ok || !context.mounted) return false;

  var clearRequests = false;
  if (plan.hasPersonRequests) {
    final answer = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Kişi istekleri sıfırlansın mı?'),
        content: Text(
          'Bu ay girilen istekler:\n${plan.personRequestSummary}\n\n'
          'Sıfırlanırsa bu istekler silinir; izinler yine korunur.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Vazgeç'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Hayır, koru'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Evet, sıfırla'),
          ),
        ],
      ),
    );
    if (answer == null) return false;
    clearRequests = answer;
  }

  final controller = ref.read(monthPlanProvider.notifier);
  if (plan.isLocked) await controller.setLocked(false);
  return controller.resetRoster(clearRequests: clearRequests);
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

enum _Regenerate { cancel, fix, regenerate }

/// Elle yapılmış değişiklikler varken yeniden oluşturma onayı.
Future<_Regenerate> _confirmManualEdits(
  BuildContext context,
  ManualEdits manual, {
  required bool canFix,
}) async {
  final more = manual.count - manual.samples.length;
  final result = await showDialog<_Regenerate>(
    context: context,
    builder: (context) => AlertDialog(
      icon: const Icon(Icons.warning_amber_rounded, color: Colors.orange),
      title: const Text('Elle yapılanlar silinecek'),
      content: SingleChildScrollView(
        child: Text(
          [
            if (manual.manualList)
              'Bu liste elle girildi ya da Excel\'den alındı. Yeniden '
                  'oluşturulursa liste baştan kurulur; girdiklerin silinir.',
            if (manual.count > 0) ...[
              'Bu listede elle yapılmış ${manual.count} değişiklik var:',
              for (final line in manual.samples) '• $line',
              if (more > 0) '… ve $more değişiklik daha.',
            ],
            if (canFix)
              '\nYalnız kural ihlallerini gidermek istiyorsan "Kurallara göre '
                  'düzelt" elle yapılanları korur.',
          ].join('\n'),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(_Regenerate.cancel),
          child: const Text('Vazgeç'),
        ),
        if (canFix)
          TextButton(
            onPressed: () => Navigator.of(context).pop(_Regenerate.fix),
            child: const Text('Kurallara göre düzelt'),
          ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_Regenerate.regenerate),
          child: const Text('Yine de oluştur'),
        ),
      ],
    ),
  );
  return result ?? _Regenerate.cancel;
}
