import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../../logic/turkish_dates.dart';
import '../../logic/yearly_summary.dart';
import '../holidays/holidays_controller.dart';
import '../people/people_controller.dart';
import 'monthly_comparison.dart';
import 'past_roster_page.dart';
import '../../shared/providers.dart';
import '../month/month_plan_controller.dart';
import '../roster/summary_table.dart';

/// İstatistik sekmesi: seçilen yılın kişi başı toplamları (nöbet, hafta
/// sonu, resmi tatil, dini bayram, gün aşırı çift, çalışılan saat, fazla
/// mesai), aylara göre karşılaştırma tablosu ve eski listeleri girme.
class StatisticsPage extends ConsumerStatefulWidget {
  const StatisticsPage({super.key});

  @override
  ConsumerState<StatisticsPage> createState() => _StatisticsPageState();
}

class _StatisticsPageState extends ConsumerState<StatisticsPage> {
  late int _year = ref.read(todayProvider).year;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Listeler değişince (oluşturma, düzenleme, eski liste girişi) yenilenir.
    ref.watch(monthPlanProvider);
    final summary = YearlySummary.build(
      year: _year,
      plans: ref.watch(monthPlanRepositoryProvider).getAll(),
      people: ref.watch(peopleProvider),
      holidays: ref.watch(holidaysProvider),
      settings: ref.watch(rosterSettingsProvider),
    );
    String fmt(num v) => SummaryTable.fmt(v);

    return Scaffold(
      appBar: AppBar(
        title: const Text('İstatistik'),
        actions: [
          IconButton(
            tooltip: 'Eski listeleri gir',
            icon: const Icon(Icons.edit_calendar_outlined),
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => PastRosterPage(initialYear: _year),
                ),
              );
              // Girilen aylar özete yansısın.
              if (mounted) setState(() {});
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                tooltip: 'Önceki yıl',
                icon: const Icon(Icons.chevron_left),
                onPressed: () => setState(() => _year--),
              ),
              Text('$_year', style: theme.textTheme.titleMedium),
              IconButton(
                tooltip: 'Sonraki yıl',
                icon: const Icon(Icons.chevron_right),
                onPressed: () => setState(() => _year++),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              summary.months.isEmpty
                  ? 'Bu yıl için oluşturulmuş liste yok. Eski listeleri '
                        'girmek için üstteki takvim simgesine dokunun.'
                  : 'Dahil aylar: '
                        '${summary.months.map((m) => turkishMonthNames[m - 1]).join(', ')}',
              style: theme.textTheme.bodyMedium,
            ),
          ),
          if (summary.rows.isNotEmpty)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columnSpacing: 20,
                headingRowHeight: 56,
                columns: const [
                  DataColumn(label: Text('Ad')),
                  DataColumn(label: Text('Görev')),
                  DataColumn(label: Text('Ay'), numeric: true),
                  DataColumn(label: Text('Toplam\nnöbet'), numeric: true),
                  DataColumn(label: Text('Hafta sonu\nnöbet'), numeric: true),
                  DataColumn(label: Text('Resmi tatil\nnöbeti'), numeric: true),
                  DataColumn(label: Text('Dini bayram\nnöbeti'), numeric: true),
                  DataColumn(label: Text('Gün aşırı\nçift'), numeric: true),
                  DataColumn(label: Text('Çalışılan\nsaat'), numeric: true),
                  DataColumn(label: Text('Fazla\nmesai'), numeric: true),
                ],
                rows: [
                  for (final r in summary.rows)
                    DataRow(
                      cells: [
                        DataCell(Text(r.name)),
                        DataCell(Text(r.role.label)),
                        DataCell(Text(fmt(r.totals.months))),
                        DataCell(Text(fmt(r.totals.shifts))),
                        DataCell(Text(fmt(r.totals.weekendShifts))),
                        DataCell(Text(fmt(r.totals.nationalHolidayShifts))),
                        DataCell(Text(fmt(r.totals.religiousHolidayShifts))),
                        DataCell(Text(fmt(r.totals.everyOtherDayPairs))),
                        DataCell(Text(fmt(r.totals.workedHours))),
                        DataCell(Text(fmt(r.totals.overtimeHours))),
                      ],
                    ),
                ],
              ),
            ),
          if (summary.rows.isNotEmpty) MonthlyComparison(summary: summary),
        ],
      ),
    );
  }
}
