import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../../logic/turkish_dates.dart';
import '../../logic/yearly_summary.dart';
import '../holidays/holidays_controller.dart';
import '../people/people_controller.dart';
import 'monthly_comparison.dart';
import 'summary_table.dart';

/// Kişi başı yıl toplamları (nöbet, hafta sonu, tatil, gün aşırı çift,
/// çalışılan saat, fazla mesai) ve aylara göre karşılaştırma tablosu.
class YearlySummaryPage extends ConsumerStatefulWidget {
  const YearlySummaryPage({super.key, required this.initialYear});

  final int initialYear;

  @override
  ConsumerState<YearlySummaryPage> createState() => _YearlySummaryPageState();
}

class _YearlySummaryPageState extends ConsumerState<YearlySummaryPage> {
  late int _year = widget.initialYear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final summary = YearlySummary.build(
      year: _year,
      plans: ref.watch(monthPlanRepositoryProvider).getAll(),
      people: ref.watch(peopleProvider),
      holidays: ref.watch(holidaysProvider),
      settings: ref.watch(rosterSettingsProvider),
    );
    String fmt(num v) => SummaryTable.fmt(v);

    return Scaffold(
      appBar: AppBar(title: const Text('Yıllık Özet')),
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
                  ? 'Bu yıl için oluşturulmuş liste yok.'
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
