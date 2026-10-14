import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../data/backup_service.dart';
import '../../data/providers.dart';
import '../../shared/platform_services.dart';
import '../../shared/providers.dart';

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
