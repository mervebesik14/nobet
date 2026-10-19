import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import 'package:intl/intl.dart';

import '../../data/auto_backup_service.dart';
import '../../data/backup_service.dart';
import '../../data/providers.dart';
import '../../shared/platform_services.dart';
import '../../shared/providers.dart';
import 'backup_actions.dart';

enum _Action { restore, share }

/// Telefona kendiliğinden alınan yedekler: geri yükle ya da paylaş.
class AutoBackupsPage extends ConsumerWidget {
  const AutoBackupsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final service = ref.watch(autoBackupServiceProvider);
    final box = ref.watch(hiveBoxesProvider).autoBackups;
    return Scaffold(
      appBar: AppBar(title: const Text('Otomatik yedekler')),
      body: ValueListenableBuilder(
        valueListenable: box.listenable(),
        builder: (context, _, _) {
          final entries = service.entries();
          return ListView(
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Text(
                  'Veri her değiştiğinde telefona kendiliğinden yedek alınır '
                  '(en son 20 yedek). Uygulama silinir ya da telefon '
                  'değişirse bunlar da gider; onun için yedeği paylaşın.',
                ),
              ),
              if (entries.isEmpty)
                const ListTile(title: Text('Henüz otomatik yedek yok.')),
              for (final e in entries)
                ListTile(
                  key: ValueKey('auto-backup-${e.at.toIso8601String()}'),
                  leading: const Icon(Icons.backup_outlined),
                  title: Text(
                    DateFormat('d MMMM y, HH:mm', 'tr_TR').format(e.at),
                  ),
                  subtitle: Text(
                    '${e.info.people} kişi, ${e.info.monthPlans} ay planı',
                  ),
                  trailing: PopupMenuButton<_Action>(
                    tooltip: 'Seçenekler',
                    onSelected: (action) => switch (action) {
                      _Action.restore => _restore(context, ref, e.at),
                      _Action.share => _share(context, ref, e.at),
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: _Action.restore,
                        child: Text('Geri yükle'),
                      ),
                      PopupMenuItem(
                        value: _Action.share,
                        child: Text('Paylaş'),
                      ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  static void _notify(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _restore(
    BuildContext context,
    WidgetRef ref,
    DateTime at,
  ) async {
    final Map<String, dynamic> backup;
    try {
      backup = ref.read(autoBackupServiceProvider).load(at);
    } on BackupFormatException catch (e) {
      _notify(context, e.message);
      return;
    }
    await confirmAndRestore(context, ref, backup);
  }

  Future<void> _share(BuildContext context, WidgetRef ref, DateTime at) async {
    try {
      final backup = ref.read(autoBackupServiceProvider).load(at);
      final text = const JsonEncoder.withIndent('  ').convert(backup);
      await ref
          .read(platformServicesProvider)
          .shareFile(
            utf8.encode(text),
            'nobet-yedek-${DateFormat('yyyy-MM-dd-HHmm').format(at)}.json',
            'application/json',
          );
      await ref
          .read(backupStatusProvider.notifier)
          .markBackedUp(ref.read(todayProvider));
    } catch (e) {
      if (context.mounted) _notify(context, 'Yedek paylaşılamadı: $e');
    }
  }
}
