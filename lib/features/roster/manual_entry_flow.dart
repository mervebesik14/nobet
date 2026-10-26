import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../../logic/roster_excel.dart';
import '../../logic/roster_generator.dart';
import '../../logic/roster_import.dart';
import '../../logic/roster_summary.dart';
import '../../logic/turkish_collation.dart';
import '../../logic/turkish_dates.dart';
import '../../logic/xlsx_reader.dart';
import '../../logic/xlsx_writer.dart';
import '../../shared/platform_services.dart';
import '../holidays/holidays_controller.dart';
import '../month/month_plan_controller.dart';
import '../people/people_controller.dart';
import 'roster_flow.dart';

enum _ManualEntry { empty, excel, template }

void _notify(BuildContext context, String message) =>
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));

/// "Listeyi elle gir": dışarıda hazırlanmış listeyi girmenin yolları. Boş
/// listeyle başlayıp tabloya dokunarak işaretleme, doldurulmuş Excel'i alma
/// ya da Excel şablonunu paylaşma. Liste kaydedildiyse (liste ekranı
/// açılmalı) true döner.
Future<bool> manualEntryFlow(BuildContext context, WidgetRef ref) async {
  final plan = ref.read(monthPlanProvider);
  if (plan.isLocked) {
    _notify(context, 'Bu ay kilitli. Elle girmek için önce kilidi açın.');
    return false;
  }
  final monthName = turkishMonthNames[plan.month - 1];
  final choice = await showModalBottomSheet<_ManualEntry>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              '$monthName listesini elle gir',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          ListTile(
            leading: const Icon(Icons.grid_on_outlined),
            title: const Text('Boş listeyle başla'),
            subtitle: const Text(
              'Tablodaki hücrelere dokunarak nöbetleri işaretle.',
            ),
            onTap: () => Navigator.of(context).pop(_ManualEntry.empty),
          ),
          ListTile(
            leading: const Icon(Icons.upload_file),
            title: const Text("Excel'den al"),
            subtitle: const Text(
              'Doldurduğun şablonu ya da uygulamadan paylaşıp Excel\'de '
              'düzenlediğin listeyi seç.',
            ),
            onTap: () => Navigator.of(context).pop(_ManualEntry.excel),
          ),
          ListTile(
            leading: const Icon(Icons.download_outlined),
            title: const Text('Excel şablonunu paylaş'),
            subtitle: const Text(
              'Kişiler ve günlerle boş tablo: nöbet günlerine 24 (ikinci '
              'teknikere 16B) yaz, sonra "Excel\'den al".',
            ),
            onTap: () => Navigator.of(context).pop(_ManualEntry.template),
          ),
        ],
      ),
    ),
  );
  if (choice == null || !context.mounted) return false;
  return switch (choice) {
    _ManualEntry.empty => _startEmpty(context, ref),
    _ManualEntry.excel => _importExcel(context, ref),
    _ManualEntry.template => _shareTemplate(context, ref).then((_) => false),
  };
}

Future<bool> _confirmReplace(BuildContext context, String message) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Mevcut liste değiştirilsin mi?'),
      content: Text(
        '$message\n\nBu ayın mevcut listesi silinip yenisiyle değiştirilecek. '
        'Değişiklik geçmişinden geri alınabilir.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Vazgeç'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Değiştir'),
        ),
      ],
    ),
  );
  return ok ?? false;
}

Future<bool> _startEmpty(BuildContext context, WidgetRef ref) async {
  final plan = ref.read(monthPlanProvider);
  if (plan.hasRoster &&
      !await _confirmReplace(context, 'Boş bir liste açılacak.')) {
    return false;
  }
  if (!context.mounted) return false;
  final bool nurseOnly;
  if (ref.read(rosterSettingsProvider).techsPerDay > 0) {
    final mode = await chooseRosterMode(context);
    if (mode == null || !context.mounted) return false;
    nurseOnly = mode;
  } else {
    nurseOnly = true;
  }
  final ok = await ref
      .read(monthPlanProvider.notifier)
      .startEmptyRoster(nurseOnly: nurseOnly);
  if (ok && context.mounted) {
    _notify(
      context,
      'Boş liste açıldı. Serbest düzenleme açık: nöbet günlerine dokunarak '
      'işaretleyin.',
    );
  }
  return ok;
}

Future<bool> _importExcel(BuildContext context, WidgetRef ref) async {
  final bytes = await ref.read(platformServicesProvider).pickExcelFile();
  if (bytes == null || !context.mounted) return false;
  final plan = ref.read(monthPlanProvider);
  final settings = ref.read(rosterSettingsProvider);
  final RosterImportResult result;
  try {
    result = RosterImport.fromRows(
      rows: XlsxReader.readSheet(bytes, preferredSheet: 'Nöbet Listesi'),
      year: plan.year,
      month: plan.month,
      people: ref.read(peopleProvider),
      techsPerDay: settings.techsPerDay,
      shiftHours: settings.shiftHours,
    );
  } on XlsxFormatException catch (e) {
    _notify(context, e.message);
    return false;
  } on RosterImportException catch (e) {
    _notify(context, e.message);
    return false;
  }
  if (result.shiftCount == 0 && result.leaveDayCount == 0) {
    _notify(context, 'Dosyada nöbet bulunamadı.');
    return false;
  }

  final monthName = turkishMonthNames[plan.month - 1];
  final nurseOnly = settings.techsPerDay == 0 || !result.hasTechShifts;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text("$monthName listesi Excel'den alınsın mı?"),
      content: SingleChildScrollView(
        child: Text(
          [
            '${result.shiftCount} nöbet, ${result.matchedPeople.length} kişi '
                'okundu.',
            if (result.leaveDayCount > 0)
              '${result.leaveDayCount} izin günü mevcut izinlere eklenecek.',
            if (nurseOnly && settings.techsPerDay > 0)
              'Teknikere nöbet yazılmamış: yalnız hemşire listesi olarak '
                  'kaydedilecek.',
            if (result.warnings.isNotEmpty)
              '\nDikkat:\n${result.warnings.map((w) => '• $w').join('\n')}',
            '\nListe olduğu gibi kaydedilir; kural ihlalleri uyarı olarak '
                'görünür.',
            if (plan.hasRoster)
              'Bu ayın mevcut listesi değiştirilecek (geçmişten geri '
                  'alınabilir).',
          ].join('\n'),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Vazgeç'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Kaydet'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return false;
  final ok = await ref
      .read(monthPlanProvider.notifier)
      .importRoster(result, nurseOnly: nurseOnly);
  if (ok && context.mounted) {
    _notify(context, "Liste Excel'den alındı.");
  }
  return ok;
}

/// Seçili ayın boş Excel şablonu: bu ay çalışan kişiler (görev sırasıyla)
/// ve günler; mevcut izinler işaretli. Biçim, paylaşılan listeyle aynıdır.
Future<void> _shareTemplate(BuildContext context, WidgetRef ref) async {
  final plan = ref.read(monthPlanProvider);
  final settings = ref.read(effectiveSettingsProvider);
  final holidays = ref
      .read(holidaysProvider)
      .where((h) => h.date.year == plan.year && h.date.month == plan.month)
      .toList();
  final people =
      ref
          .read(peopleProvider)
          .where((p) => p.worksInMonth(plan.year, plan.month))
          .toList()
        ..sort((a, b) {
          final r = a.role.index.compareTo(b.role.index);
          return r != 0 ? r : compareTurkish(a.name, b.name);
        });
  final empty = plan.copyWith(assignments: const {});
  final bytes = RosterExcel.build(
    plan: empty,
    rows: [for (final p in people) (id: p.id, name: p.name, role: p.role)],
    summary: RosterSummary.build(
      year: plan.year,
      month: plan.month,
      assignments: const {},
      people: people,
      holidays: holidays,
      settings: settings,
    ),
    weekendDays: RosterGenerator.weekendDays(
      plan.year,
      plan.month,
      holidays,
      settings,
    ),
    holidayDays: {
      for (final h in holidays)
        if (!h.isHalfDay) h.date.day,
    },
    shiftHours: settings.shiftHours,
    includeSummary: false,
  );
  try {
    await ref
        .read(platformServicesProvider)
        .shareFile(
          bytes,
          'nobet-sablon-${plan.year}-${plan.month.toString().padLeft(2, '0')}.xlsx',
          XlsxWriter.mimeType,
        );
  } catch (e) {
    if (context.mounted) _notify(context, 'Paylaşılamadı: $e');
  }
}
