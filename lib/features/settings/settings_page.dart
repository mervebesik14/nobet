import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../data/backup_service.dart';
import '../../data/providers.dart';
import '../../logic/next_month_reminder.dart';
import '../../models/models.dart';
import '../../shared/notification_service.dart';
import '../../shared/platform_services.dart';
import '../month/month_reminder_notifications.dart';
import 'auto_backups_page.dart';
import 'backup_actions.dart';

/// Ayarlar sekmesi: nöbet kuralları, mesai hesabı, tema ve yedekleme.
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  static String _hours(num v) => NumberFormat('#,##0.#', 'tr_TR').format(v);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(rosterSettingsProvider);
    final controller = ref.read(rosterSettingsProvider.notifier);
    final themeMode = ref.watch(themeModeProvider);
    final reminderDay = ref.watch(monthReminderDayProvider);
    void update(RosterSettings next) => controller.update(next);

    return Scaffold(
      appBar: AppBar(title: const Text('Ayarlar')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          const _Header('Nöbet kuralları'),
          _NumberSetting(
            title: 'Günlük hemşire sayısı',
            value: s.nursesPerDay,
            min: 1,
            max: 4,
            onChanged: (v) => update(s.copyWith(nursesPerDay: v.toInt())),
          ),
          _NumberSetting(
            title: 'Günlük radyoloji teknikeri sayısı',
            subtitle: s.techsPerDay >= 2
                ? 'İki tekniker: biri 24, biri 16B. 24 çalışan ertesi gün '
                      'çalışamaz; 16B çalışabilir.'
                : null,
            value: s.techsPerDay,
            min: 0,
            max: 2,
            onChanged: (v) => update(s.copyWith(techsPerDay: v.toInt())),
          ),
          if (s.techsPerDay >= 2)
            _NumberSetting(
              title: '16B vardiyası çalışma saati',
              value: s.secondaryTechShiftHours,
              min: 1,
              max: 24,
              suffix: 'saat',
              onChanged: (v) =>
                  update(s.copyWith(secondaryTechShiftHours: v.toInt())),
            ),
          SwitchListTile(
            title: const Text('Art arda gün yasağı'),
            subtitle: const Text(
              'Aynı kişiye art arda iki gün nöbet verilmez.',
            ),
            value: s.forbidConsecutiveDays,
            onChanged: (v) => update(s.copyWith(forbidConsecutiveDays: v)),
          ),
          _NumberSetting(
            title: 'Gün aşırı zincir: en fazla',
            subtitle: s.maxEveryOtherDayChain == 2
                ? '3-5 olur, 3-5-7 olmaz.'
                : 'Gün aşırı art arda en fazla ${s.maxEveryOtherDayChain} '
                      'nöbet.',
            value: s.maxEveryOtherDayChain,
            min: 1,
            max: 6,
            suffix: 'nöbet',
            onChanged: (v) =>
                update(s.copyWith(maxEveryOtherDayChain: v.toInt())),
          ),
          SwitchListTile(
            title: const Text('Fazla nöbet sınırı'),
            subtitle: Text(
              s.maxExtraOverAverage == null
                  ? 'Kapalı.'
                  : 'Kişi, grup ortalamasından en fazla '
                        '${s.maxExtraOverAverage} fazla nöbet tutar.',
            ),
            value: s.maxExtraOverAverage != null,
            onChanged: (v) => update(
              v
                  ? s.copyWith(maxExtraOverAverage: 2)
                  : s.copyWith(clearMaxExtraOverAverage: true),
            ),
          ),
          if (s.maxExtraOverAverage != null)
            _NumberSetting(
              title: 'Ortalamanın üstünde en fazla',
              value: s.maxExtraOverAverage!,
              min: 0,
              max: 5,
              suffix: 'nöbet',
              onChanged: (v) =>
                  update(s.copyWith(maxExtraOverAverage: v.toInt())),
            ),
          SwitchListTile(
            title: const Text('Resmi tatili hafta sonu say'),
            subtitle: const Text(
              'Tam gün tatiller hafta sonu nöbeti olarak sayılır.',
            ),
            value: s.holidayCountsAsWeekend,
            onChanged: (v) => update(s.copyWith(holidayCountsAsWeekend: v)),
          ),
          const _Header('Mesai hesabı'),
          _NumberSetting(
            title: 'Nöbet süresi',
            value: s.shiftHours,
            min: 1,
            max: 24,
            suffix: 'saat',
            onChanged: (v) => update(s.copyWith(shiftHours: v.toInt())),
          ),
          _NumberSetting(
            title: 'Günlük çalışma saati',
            subtitle: 'Tatil olmayan her hafta içi gün için.',
            value: s.dailyRequiredHours,
            min: 0.5,
            max: 12,
            step: 0.5,
            suffix: 'saat',
            format: _hours,
            onChanged: (v) => update(s.copyWith(dailyRequiredHours: v)),
          ),
          SwitchListTile(
            title: const Text('Arifeyi yarım gün say'),
            subtitle: Text(
              s.halfDayHolidayIsHalfWorkday
                  ? 'Arife günü ${_hours(s.halfDayRequiredHours)} saat sayılır.'
                  : 'Arife tam iş günü sayılır.',
            ),
            value: s.halfDayHolidayIsHalfWorkday,
            onChanged: (v) =>
                update(s.copyWith(halfDayHolidayIsHalfWorkday: v)),
          ),
          if (s.halfDayHolidayIsHalfWorkday)
            _NumberSetting(
              title: 'Arife günü çalışma saati',
              value: s.halfDayRequiredHours,
              min: 0,
              max: 12,
              step: 0.5,
              suffix: 'saat',
              format: _hours,
              onChanged: (v) => update(s.copyWith(halfDayRequiredHours: v)),
            ),
          ListTile(
            leading: const Icon(Icons.restart_alt),
            title: const Text('Varsayılanlara dön'),
            onTap: () => controller.reset(),
          ),
          const _Header('Görünüm'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(
                  value: ThemeMode.system,
                  label: Text('Sistem'),
                  icon: Icon(Icons.brightness_auto),
                ),
                ButtonSegment(
                  value: ThemeMode.light,
                  label: Text('Açık'),
                  icon: Icon(Icons.light_mode),
                ),
                ButtonSegment(
                  value: ThemeMode.dark,
                  label: Text('Koyu'),
                  icon: Icon(Icons.dark_mode),
                ),
              ],
              selected: {themeMode},
              onSelectionChanged: (v) =>
                  ref.read(themeModeProvider.notifier).set(v.single),
            ),
          ),
          const _Header('Bildirimler'),
          SwitchListTile(
            key: const ValueKey('month-reminder-switch'),
            secondary: const Icon(Icons.notifications_active_outlined),
            title: const Text('Ay başı hatırlatması'),
            subtitle: Text(
              'Her ayın ${NextMonthReminder.dayLabel(reminderDay)} saat '
              '10:00\'da, gelecek ayın listesi henüz oluşturulmadıysa '
              'elektroşok sesiyle bildirim gelir.',
            ),
            isThreeLine: true,
            value: ref.watch(monthReminderEnabledProvider),
            onChanged: (v) =>
                ref.read(monthReminderEnabledProvider.notifier).set(v),
          ),
          ListTile(
            key: const ValueKey('month-reminder-day'),
            leading: const Icon(Icons.event_outlined),
            title: const Text('Bildirim günü'),
            subtitle: Text(
              'Her ayın ${NextMonthReminder.dayLabel(reminderDay)}. Ay '
              'ekranındaki hatırlatma da bu günden itibaren çıkar.',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _pickReminderDay(context, ref, reminderDay),
          ),
          ListTile(
            leading: const Icon(Icons.volume_up_outlined),
            title: const Text('Bildirimi dene'),
            subtitle: const Text('Şimdi bir deneme bildirimi gelir.'),
            onTap: () => _testNotification(context, ref),
          ),
          const _Header('Yedekleme'),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              'Veriler yalnızca bu telefonda saklanır. Telefon değişirse ya da '
              'uygulama silinirse kaybolmasın diye düzenli yedek alın.',
            ),
          ),
          ListTile(
            leading: const Icon(Icons.upload_file),
            title: const Text('Yedeği dışa aktar'),
            subtitle: Text(
              'Tüm veriler tek bir JSON dosyası olarak.\n'
              '${_lastBackupText(ref.watch(backupStatusProvider).lastBackup)}',
            ),
            isThreeLine: true,
            onTap: () => exportBackup(context, ref),
          ),
          ListTile(
            leading: const Icon(Icons.restore),
            title: const Text('Yedekten geri yükle'),
            subtitle: const Text('Mevcut verilerin üzerine yazar.'),
            onTap: () => _restore(context, ref),
          ),
          ListTile(
            leading: const Icon(Icons.history_toggle_off),
            title: const Text('Otomatik yedekler'),
            subtitle: const Text(
              'Her değişiklikte telefona kendiliğinden alınır; yanlışlıkla '
              'silinen ya da bozulan veriyi geri getirir.',
            ),
            isThreeLine: true,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const AutoBackupsPage()),
            ),
          ),
        ],
      ),
    );
  }

  static String _lastBackupText(DateTime? last) => last == null
      ? 'Henüz yedek alınmadı.'
      : 'Son yedek: ${DateFormat('d MMMM y', 'tr_TR').format(last)}';

  static Future<void> _pickReminderDay(
    BuildContext context,
    WidgetRef ref,
    int current,
  ) async {
    final day = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Bildirim günü'),
        content: SingleChildScrollView(
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (var d = 1; d <= NextMonthReminder.maxDay; d++)
                ChoiceChip(
                  key: ValueKey('reminder-day-$d'),
                  label: SizedBox(
                    width: 24,
                    child: Text('$d', textAlign: TextAlign.center),
                  ),
                  showCheckmark: false,
                  selected: d == current,
                  onSelected: (_) => Navigator.of(context).pop(d),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Vazgeç'),
          ),
        ],
      ),
    );
    if (day != null) await ref.read(monthReminderDayProvider.notifier).set(day);
  }

  static Future<void> _testNotification(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final service = ref.read(notificationServiceProvider);
    try {
      final allowed = await service.requestPermission();
      if (!allowed) {
        if (context.mounted) {
          _notify(
            context,
            'Bildirim izni yok. Telefonun Ayarlar > Bildirimler > Nöbetçi '
            'bölümünden izin verin.',
          );
        }
        return;
      }
      await service.show(
        id: monthReminderFirstId - 1,
        title: 'Nöbetçi',
        body: 'Deneme: ay başı hatırlatması böyle gelecek.',
      );
    } catch (e) {
      if (context.mounted) _notify(context, 'Bildirim gönderilemedi: $e');
    }
  }

  static void _notify(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _restore(BuildContext context, WidgetRef ref) async {
    final bytes = await ref.read(platformServicesProvider).pickJsonFile();
    if (bytes == null || !context.mounted) return;

    final Map<String, dynamic> backup;
    try {
      backup = BackupService.parse(utf8.decode(bytes));
    } on BackupFormatException catch (e) {
      _notify(context, e.message);
      return;
    } on FormatException {
      _notify(context, 'Dosya okunamadı.');
      return;
    }

    await confirmAndRestore(context, ref, backup);
  }
}

class _Header extends StatelessWidget {
  const _Header(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Text(
        title,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}

/// − değer + biçiminde sayı ayarı.
class _NumberSetting extends StatelessWidget {
  const _NumberSetting({
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.subtitle,
    this.step = 1,
    this.suffix,
    this.format,
  });

  final String title;
  final String? subtitle;
  final num value;
  final num min;
  final num max;
  final num step;
  final String? suffix;
  final String Function(num)? format;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final text = format?.call(value) ?? '$value';
    return ListTile(
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle!),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: '$title azalt',
            icon: const Icon(Icons.remove_circle_outline),
            onPressed: value - step < min
                ? null
                : () => onChanged((value - step).toDouble()),
          ),
          SizedBox(
            width: 64,
            child: Text(
              suffix == null ? text : '$text $suffix',
              textAlign: TextAlign.center,
            ),
          ),
          IconButton(
            tooltip: '$title artır',
            icon: const Icon(Icons.add_circle_outline),
            onPressed: value + step > max
                ? null
                : () => onChanged((value + step).toDouble()),
          ),
        ],
      ),
    );
  }
}
