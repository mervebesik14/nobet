import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../data/backup_service.dart';
import '../../data/providers.dart';
import '../../models/models.dart';
import '../../shared/platform_services.dart';
import '../../shared/providers.dart';
import '../holidays/holidays_controller.dart';
import '../month/month_plan_controller.dart';
import '../people/people_controller.dart';

/// Ayarlar sekmesi: nöbet kuralları, mesai hesabı, tema ve yedekleme.
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  static String _hours(num v) => NumberFormat('#,##0.#', 'tr_TR').format(v);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(rosterSettingsProvider);
    final controller = ref.read(rosterSettingsProvider.notifier);
    final themeMode = ref.watch(themeModeProvider);
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
            value: s.techsPerDay,
            min: 0,
            max: 1,
            onChanged: (v) => update(s.copyWith(techsPerDay: v.toInt())),
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
            subtitle: const Text('Tüm veriler tek bir JSON dosyası olarak.'),
            onTap: () => _export(context, ref),
          ),
          ListTile(
            leading: const Icon(Icons.restore),
            title: const Text('Yedekten geri yükle'),
            subtitle: const Text('Mevcut verilerin üzerine yazar.'),
            onTap: () => _restore(context, ref),
          ),
        ],
      ),
    );
  }

  static void _notify(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _export(BuildContext context, WidgetRef ref) async {
    final now = ref.read(todayProvider);
    final text = BackupService(ref.read(hiveBoxesProvider)).exportJson();
    final name = 'nobet-yedek-${DateFormat('yyyy-MM-dd').format(now)}.json';
    try {
      await ref
          .read(platformServicesProvider)
          .shareFile(utf8.encode(text), name, 'application/json');
    } catch (e) {
      if (context.mounted) _notify(context, 'Yedek paylaşılamadı: $e');
    }
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
    if (confirmed != true) return;

    try {
      await BackupService(ref.read(hiveBoxesProvider)).restore(backup);
    } on BackupFormatException catch (e) {
      if (context.mounted) _notify(context, e.message);
      return;
    }
    // Ekranlar yeni veriyi okusun.
    ref
      ..invalidate(peopleProvider)
      ..invalidate(holidaysProvider)
      ..invalidate(monthPlanProvider)
      ..invalidate(rosterSettingsProvider)
      ..invalidate(themeModeProvider);
    if (context.mounted) _notify(context, 'Yedek geri yüklendi.');
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
