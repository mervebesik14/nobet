import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../data/providers.dart';
import '../../data/turkish_holidays.dart';
import '../../logic/work_hours_calculator.dart';
import '../../models/models.dart';
import '../../shared/widgets/month_selector.dart';
import 'holiday_form_dialog.dart';
import 'holidays_controller.dart';

/// Tatiller sekmesi: ay seçici, ayın gereken çalışma saati ve tatil listesi.
class HolidaysPage extends ConsumerWidget {
  const HolidaysPage({super.key});

  Future<void> _add(
    BuildContext context,
    WidgetRef ref,
    DateTime month,
    List<Holiday> monthHolidays,
  ) async {
    final holiday = await showDialog<Holiday>(
      context: context,
      builder: (_) => HolidayFormDialog(
        month: month,
        takenDays: {for (final h in monthHolidays) h.date.day},
      ),
    );
    if (holiday != null) {
      await ref.read(holidaysProvider.notifier).add(holiday);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = ref.watch(holidayMonthProvider);
    final monthHolidays = ref
        .watch(holidaysProvider)
        .where((h) => h.date.year == month.year && h.date.month == month.month)
        .toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Tatiller')),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Tatil ekle',
        onPressed: () => _add(context, ref, month, monthHolidays),
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          MonthSelector(
            month: month,
            onChanged: ref.read(holidayMonthProvider.notifier).select,
          ),
          _RequiredHoursCard(month: month, holidays: monthHolidays),
          if (!TurkishHolidays.hasReligiousHolidays(month.year))
            _MissingReligiousNotice(year: month.year),
          Expanded(
            child: monthHolidays.isEmpty
                ? Center(
                    child: Text(
                      'Bu ay resmi tatil yok.',
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.only(bottom: 88),
                    children: [
                      for (final h in monthHolidays) _HolidayTile(holiday: h),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

String _formatHours(double hours) =>
    NumberFormat.decimalPattern('tr_TR').format(hours);

class _RequiredHoursCard extends ConsumerWidget {
  const _RequiredHoursCard({required this.month, required this.holidays});

  final DateTime month;
  final List<Holiday> holidays;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(rosterSettingsProvider);
    final r = WorkHoursCalculator(
      settings,
    ).requiredHoursBreakdown(month.year, month.month, holidays);
    final theme = Theme.of(context);
    final details = [
      '${r.fullWorkdays} iş günü × '
          '${_formatHours(settings.dailyRequiredHours)} saat',
      if (r.halfWorkdays > 0)
        '${r.halfWorkdays} arife × '
            '${_formatHours(settings.halfDayRequiredHours)} saat',
    ].join(' + ');

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      color: theme.colorScheme.primaryContainer,
      child: ListTile(
        leading: Icon(
          Icons.schedule,
          color: theme.colorScheme.onPrimaryContainer,
        ),
        title: Text(
          'Bu ay çalışılması gereken: ${_formatHours(r.hours)} saat',
          style: TextStyle(color: theme.colorScheme.onPrimaryContainer),
        ),
        subtitle: Text(
          details,
          style: TextStyle(color: theme.colorScheme.onPrimaryContainer),
        ),
      ),
    );
  }
}

class _MissingReligiousNotice extends StatelessWidget {
  const _MissingReligiousNotice({required this.year});

  final int year;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      color: theme.colorScheme.tertiaryContainer,
      child: ListTile(
        leading: Icon(
          Icons.info_outline,
          color: theme.colorScheme.onTertiaryContainer,
        ),
        title: Text(
          '$year için Ramazan ve Kurban Bayramı tarihleri tanımlı değil. '
          'Diyanet takvimine göre + ile elle ekleyin.',
          style: TextStyle(color: theme.colorScheme.onTertiaryContainer),
        ),
      ),
    );
  }
}

enum _HolidayAction { toggleHalfDay, delete }

class _HolidayTile extends ConsumerWidget {
  const _HolidayTile({required this.holiday});

  final Holiday holiday;

  Future<void> _onAction(
    BuildContext context,
    WidgetRef ref,
    _HolidayAction action,
  ) async {
    final controller = ref.read(holidaysProvider.notifier);
    switch (action) {
      case _HolidayAction.toggleHalfDay:
        await controller.toggleHalfDay(holiday);
      case _HolidayAction.delete:
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Tatil silinsin mi?'),
            content: Text(
              '${DateFormat('d MMMM', 'tr_TR').format(holiday.date)}: '
              '${holiday.name}',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Vazgeç'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Sil'),
              ),
            ],
          ),
        );
        if (confirmed == true) await controller.delete(holiday);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final weekday = holiday.date.weekday;
    final isWeekend =
        weekday == DateTime.saturday || weekday == DateTime.sunday;
    final details = [
      holiday.isHalfDay ? 'Yarım gün' : 'Tam gün',
      if (isWeekend) 'hafta sonu',
      if (!holiday.isPredefined) 'elle eklendi',
    ].join(' · ');

    return ListTile(
      leading: SizedBox(
        width: 40,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('${holiday.date.day}', style: theme.textTheme.titleMedium),
            Text(
              DateFormat.E('tr_TR').format(holiday.date),
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
      title: Text(holiday.name),
      subtitle: Text(details),
      trailing: PopupMenuButton<_HolidayAction>(
        tooltip: 'Seçenekler',
        onSelected: (a) => _onAction(context, ref, a),
        itemBuilder: (_) => [
          PopupMenuItem(
            value: _HolidayAction.toggleHalfDay,
            child: Text(holiday.isHalfDay ? 'Tam gün yap' : 'Yarım gün yap'),
          ),
          const PopupMenuItem(value: _HolidayAction.delete, child: Text('Sil')),
        ],
      ),
    );
  }
}
