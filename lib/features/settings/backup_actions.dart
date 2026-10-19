import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../data/backup_service.dart';
import '../../data/providers.dart';
import '../../shared/platform_services.dart';
import '../../shared/providers.dart';
import '../holidays/holidays_controller.dart';
import '../month/month_plan_controller.dart';
import '../people/people_controller.dart';

/// Tüm verileri JSON yedek olarak paylaşır; başarılıysa son yedek tarihini
/// kaydeder (hatırlatma sıfırlanır).
Future<bool> exportBackup(BuildContext context, WidgetRef ref) async {
  final now = ref.read(todayProvider);
  final text = BackupService(ref.read(hiveBoxesProvider)).exportJson();
  final name = 'nobet-yedek-${DateFormat('yyyy-MM-dd').format(now)}.json';
  try {
    await ref
        .read(platformServicesProvider)
        .shareFile(utf8.encode(text), name, 'application/json');
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('Yedek paylaşılamadı: $e')));
    }
    return false;
  }
  await ref.read(backupStatusProvider.notifier).markBackedUp(now);
  return true;
}

void _notify(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// Yedeğin özetini gösterip onay ister; onaylanırsa tüm veriyi yedektekiyle
/// değiştirir. Geri yüklendiyse true.
Future<bool> confirmAndRestore(
  BuildContext context,
  WidgetRef ref,
  Map<String, dynamic> backup,
) async {
  final info = BackupService.info(backup);
  final date = info.exportedAt == null
      ? ''
      : '${DateFormat('d MMMM y HH:mm', 'tr_TR').format(info.exportedAt!)}\n';
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Yedekten geri yüklensin mi?'),
      content: Text(
        '${date}Yedekte ${info.people} kişi, ${info.monthPlans} ay planı ve '
        '${info.holidays} tatil var.\n\n'
        'Bu telefondaki tüm veriler silinip yedektekiyle değiştirilecek.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Vazgeç'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Geri yükle'),
        ),
      ],
    ),
  );
  if (confirmed != true) return false;

  try {
    await BackupService(ref.read(hiveBoxesProvider)).restore(backup);
  } on BackupFormatException catch (e) {
    if (context.mounted) _notify(context, e.message);
    return false;
  }
  // Ekranlar yeni veriyi okusun.
  ref
    ..invalidate(peopleProvider)
    ..invalidate(holidaysProvider)
    ..invalidate(monthPlanProvider)
    ..invalidate(rosterSettingsProvider)
    ..invalidate(themeModeProvider);
  if (context.mounted) _notify(context, 'Yedek geri yüklendi.');
  return true;
}
