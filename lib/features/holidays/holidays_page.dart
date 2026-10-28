import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../data/providers.dart';
import '../../data/turkish_holidays.dart';
import '../../logic/work_hours_calculator.dart';
import '../../models/models.dart';
import '../../shared/brand.dart';
import '../../shared/widgets/brand_widgets.dart';
import 'holiday_form_dialog.dart';
import 'holidays_controller.dart';
import '../../shared/app_colors.dart';

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
      appBar: BrandHeader(
        title: 'Tatiller',
        bottom: HeaderMonthSelector(
          month: month,
          onChanged: ref.read(holidayMonthProvider.notifier).select,
        ),
      ),
      floatingActionButton: FloatingActionButton(
        // Sekmeler birlikte durduğu için kahraman geçişi yok.
        heroTag: null,
        tooltip: 'Tatil ekle',
        onPressed: () => _add(context, ref, month, monthHolidays),
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          const SizedBox(height: 8),
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
                    padding: const EdgeInsets.only(bottom: 96),
                    children: [
                      const PillHeader('Bu ayki tatiller'),
                      GroupCard(
                        children: [
                          for (final h in monthHolidays)
                            _HolidayTile(holiday: h),
                        ],
                      ),
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

    final brand = context.brand;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: brand.featureGradient,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: brand.onHeader.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(Icons.schedule, color: brand.onHeader),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Ekran okuyucu ve testler için tam cümle; görünen büyük sayı.
                Semantics(
                  label:
                      'Bu ay çalışılması gereken: ${_formatHours(r.hours)} saat',
                  excludeSemantics: true,
                  child: Text(
                    '${_formatHours(r.hours)} saat',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: brand.onHeader,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Bu ay çalışılması gereken · $details',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: brand.onHeaderMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
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
      color: theme.colorScheme.holidayTint,
      child: ListTile(
        leading: Icon(Icons.info_outline, color: theme.colorScheme.onSurface),
        title: Text(
          '$year için Ramazan ve Kurban Bayramı tarihleri tanımlı değil. '
          'Diyanet takvimine göre + ile elle ekleyin.',
        ),
      ),
    );
  }
}

enum _HolidayAction { toggleHalfDay, toggleReligious, delete }

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
      case _HolidayAction.toggleReligious:
        await controller.toggleReligious(holiday);
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
      holiday.isReligious ? 'Dini bayram' : 'Resmi tatil',
      holiday.isHalfDay ? 'Yarım gün' : 'Tam gün',
      if (isWeekend) 'hafta sonu',
      if (!holiday.isPredefined) 'elle eklendi',
    ].join(' · ');

    return ListTile(
      leading: SizedBox(
        width: 40,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '${holiday.date.day}',
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w700,
                fontSize: 19,
                height: 1,
              ),
            ),
            Text(
              DateFormat.E('tr_TR').format(holiday.date),
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
      title: Text(holiday.name),
      subtitle: Row(
        children: [
          Container(
            width: 7,
            height: 7,
            margin: const EdgeInsets.only(right: 6),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: holiday.isHalfDay
                  ? const Color(0xFFE0A030)
                  : theme.colorScheme.primary,
            ),
          ),
          Expanded(child: Text(details)),
        ],
      ),
      trailing: PopupMenuButton<_HolidayAction>(
        icon: const Icon(Icons.more_horiz),
        style: IconButton.styleFrom(
          backgroundColor: theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: 0.5,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        tooltip: 'Seçenekler',
        onSelected: (a) => _onAction(context, ref, a),
        itemBuilder: (_) => [
          PopupMenuItem(
            value: _HolidayAction.toggleHalfDay,
            child: Text(holiday.isHalfDay ? 'Tam gün yap' : 'Yarım gün yap'),
          ),
          PopupMenuItem(
            value: _HolidayAction.toggleReligious,
            child: Text(
              holiday.isReligious ? 'Resmi tatil yap' : 'Dini bayram yap',
            ),
          ),
          const PopupMenuItem(value: _HolidayAction.delete, child: Text('Sil')),
        ],
      ),
    );
  }
}
