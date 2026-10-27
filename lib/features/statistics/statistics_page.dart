import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../../logic/turkish_dates.dart';
import '../../logic/xlsx_writer.dart';
import '../../logic/yearly_excel.dart';
import '../../logic/yearly_summary.dart';
import '../../models/models.dart';
import '../../shared/brand.dart';
import '../../shared/platform_services.dart';
import '../../shared/widgets/brand_widgets.dart';
import '../holidays/holidays_controller.dart';
import '../people/people_controller.dart';
import 'monthly_comparison.dart';
import 'past_roster_page.dart';
import 'statistics_pdf.dart';
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

enum _ShareAction { pdf, excel }

class _StatisticsPageState extends ConsumerState<StatisticsPage> {
  late int _year = ref.read(todayProvider).year;

  void _notify(String message) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));

  /// Yıllık özeti PDF ya da Excel olarak paylaşır.
  Future<void> _share(_ShareAction action, YearlySummary summary) async {
    if (summary.rows.isEmpty) {
      _notify('$_year için paylaşılacak liste yok.');
      return;
    }
    final services = ref.read(platformServicesProvider);
    final base = 'nobet-istatistik-$_year';
    try {
      switch (action) {
        case _ShareAction.pdf:
          final fonts = await services.loadPdfFonts();
          final pdf = await buildStatisticsPdf(
            year: _year,
            summary: summary,
            font: fonts.regular,
            boldFont: fonts.bold,
          );
          await services.sharePdf(pdf, '$base.pdf');
        case _ShareAction.excel:
          await services.shareFile(
            YearlyExcel.build(year: _year, summary: summary),
            '$base.xlsx',
            XlsxWriter.mimeType,
          );
      }
    } catch (e) {
      if (mounted) _notify('Paylaşılamadı: $e');
    }
  }

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

    final brand = context.brand;
    final maxShifts = summary.rows.fold<num>(
      0,
      (m, r) => r.totals.shifts > m ? r.totals.shifts : m,
    );
    final sorted = [...summary.rows]
      ..sort((a, b) => b.totals.shifts.compareTo(a.totals.shifts));

    return Scaffold(
      appBar: BrandHeader(
        title: 'İstatistik',
        actions: [
          PopupMenuButton<_ShareAction>(
            tooltip: 'Paylaş',
            icon: Icon(Icons.share, color: brand.onHeader),
            style: IconButton.styleFrom(
              backgroundColor: brand.onHeader.withValues(alpha: 0.14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              fixedSize: const Size(44, 44),
            ),
            onSelected: (action) => _share(action, summary),
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: _ShareAction.pdf,
                child: ListTile(
                  leading: Icon(Icons.picture_as_pdf_outlined),
                  title: Text('PDF olarak paylaş'),
                ),
              ),
              PopupMenuItem(
                value: _ShareAction.excel,
                child: ListTile(
                  leading: Icon(Icons.table_view_outlined),
                  title: Text('Excel olarak paylaş'),
                ),
              ),
            ],
          ),
          HeaderIconButton(
            tooltip: 'Eski listeleri gir',
            icon: Icons.edit_calendar_outlined,
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
        bottom: HeaderSelector(
          label: '$_year',
          previousTooltip: 'Önceki yıl',
          nextTooltip: 'Sonraki yıl',
          onPrevious: () => setState(() => _year--),
          onNext: () => setState(() => _year++),
        ),
        footer: summary.months.isEmpty
            ? null
            : 'Dahil aylar: '
                  '${summary.months.map((m) => turkishMonthNames[m - 1]).join(', ')}',
      ),
      body: ListView(
        padding: const EdgeInsets.only(top: 4, bottom: 24),
        children: [
          if (summary.months.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Bu yıl için oluşturulmuş liste yok. Eski listeleri '
                'girmek için üstteki takvim simgesine dokunun.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
            ),
          if (summary.rows.isNotEmpty) ...[
            const PillHeader('Nöbet dağılımı', end: 'Toplam nöbet · yıl'),
            GroupCard(
              children: [
                for (final r in sorted)
                  _ShareBar(
                    name: r.name,
                    role: r.role,
                    months: r.totals.months,
                    shifts: r.totals.shifts,
                    max: maxShifts,
                  ),
              ],
            ),
            const PillHeader('Ayrıntılı tablo'),
          ],
          if (summary.rows.isNotEmpty)
            Card(
              child: SingleChildScrollView(
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
                    DataColumn(
                      label: Text('Resmi tatil\nnöbeti'),
                      numeric: true,
                    ),
                    DataColumn(
                      label: Text('Dini bayram\nnöbeti'),
                      numeric: true,
                    ),
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
            ),
          if (summary.rows.isNotEmpty) MonthlyComparison(summary: summary),
        ],
      ),
    );
  }
}

/// Kişinin yıllık toplam nöbeti: ad, görev etiketi, ay sayısı ve çubuk.
class _ShareBar extends StatelessWidget {
  const _ShareBar({
    required this.name,
    required this.role,
    required this.months,
    required this.shifts,
    required this.max,
  });

  final String name;
  final Role role;
  final num months;
  final num shifts;
  final num max;

  static const _techColor = Color(0xFF3F51B5);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brand = context.brand;
    final isTech = role == Role.radiologyTech;
    final color = isTech ? _techColor : brand.stepper;
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Expanded(
            flex: 5,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: isTech
                            ? _techColor.withValues(alpha: 0.12)
                            : brand.pill,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        isTech ? 'Rad. Tek.' : role.label,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: isTech ? _techColor : brand.onPill,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text('${SummaryTable.fmt(months)} ay', style: muted),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 4,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: max == 0 ? 0 : (shifts / max).toDouble(),
                minHeight: 8,
                color: color,
                backgroundColor: theme.colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.6),
              ),
            ),
          ),
          SizedBox(
            width: 44,
            child: Text(
              SummaryTable.fmt(shifts),
              textAlign: TextAlign.right,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
