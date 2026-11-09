import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../../logic/every_other_day_chains.dart';
import '../../logic/fatigue_score.dart';
import '../../logic/leave_balance.dart';
import '../../logic/request_fulfillment.dart';
import '../../logic/file_names.dart';
import '../../logic/totals_columns.dart';
import '../../logic/turkish_dates.dart';
import '../../logic/xlsx_writer.dart';
import '../../logic/yearly_excel.dart';
import '../../logic/yearly_summary.dart';
import '../../models/models.dart';
import '../../shared/brand.dart';
import '../../shared/platform_services.dart';
import '../../shared/widgets/column_picker_dialog.dart';
import '../../shared/widgets/pdf_preview_page.dart';
import '../../shared/widgets/brand_widgets.dart';
import '../holidays/holidays_controller.dart';
import '../people/leave_balance_provider.dart';
import '../people/people_controller.dart';
import 'monthly_comparison.dart';
import 'person_report_pdf.dart';
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

enum _ShareAction { pdf, excel, personReport }

class _StatisticsPageState extends ConsumerState<StatisticsPage> {
  late int _year = ref.read(todayProvider).year;

  static const _reportColumnsKey = 'reportCardColumns';

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
          if (!mounted) return;
          // Önce önizleme; "Paylaş" ile gönderilir.
          await Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => PdfPreviewPage(
                title: '$_year yıllık özet',
                pdf: pdf,
                fileName: '$base.pdf',
              ),
            ),
          );
        case _ShareAction.personReport:
          final row = await showDialog<YearlyRow>(
            context: context,
            builder: (context) => SimpleDialog(
              title: const Text('Kimin karnesi?'),
              children: [
                for (final r in summary.rows)
                  SimpleDialogOption(
                    onPressed: () => Navigator.of(context).pop(r),
                    child: Text(r.name),
                  ),
              ],
            ),
          );
          if (row == null || !mounted) return;
          final meta = ref.read(hiveBoxesProvider).meta;
          final saved = meta.get(_reportColumnsKey);
          final columns = await showDialog<Set<TotalsColumn>>(
            context: context,
            builder: (_) => ColumnPickerDialog<TotalsColumn>(
              title: 'Karnede hangi sütunlar olsun?',
              intro:
                  'Ay her zaman yazılır; özet kutuları da seçilen '
                  'sütunlara göre çıkar. Seçimin hatırlanır.',
              options: [for (final c in TotalsColumn.values) (c, c.label)],
              initial: saved is List
                  ? TotalsColumn.fromNames(saved.cast<String>())
                  : {...TotalsColumn.values},
              confirmLabel: 'Önizle',
            ),
          );
          if (columns == null || !mounted) return;
          await meta.put(_reportColumnsKey, [for (final c in columns) c.name]);
          final fonts = await services.loadPdfFonts();
          final pdf = await buildPersonReportPdf(
            columns: columns,
            year: _year,
            row: row,
            summary: summary,
            font: fonts.regular,
            boldFont: fonts.bold,
            createdAt: ref.read(todayProvider),
          );
          if (!mounted) return;
          // Önce önizleme: ne gönderildiği görülsün.
          await Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => PdfPreviewPage(
                title: '${row.name} · karne',
                pdf: pdf,
                fileName: 'karne-${fileSlug(row.name)}-$_year.pdf',
              ),
            ),
          );
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
    final requests = RequestFulfillment.forYear(
      year: _year,
      plans: ref.watch(monthPlanRepositoryProvider).getAll(),
      people: ref.watch(peopleProvider),
    );

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
                  title: Text('PDF (önizle ve paylaş)'),
                ),
              ),
              PopupMenuItem(
                value: _ShareAction.personReport,
                child: ListTile(
                  leading: Icon(Icons.badge_outlined),
                  title: Text('Kişi karnesi (önizle ve paylaş)'),
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
                    DataColumn(label: Text('Gün aşırı\ngün'), numeric: true),
                    DataColumn(label: Text('En uzun\nzincir'), numeric: true),
                    DataColumn(label: Text('Yorgun-\nluk'), numeric: true),
                    DataColumn(label: Text('7A\ngün'), numeric: true),
                    DataColumn(label: Text('Geldiği\ngün'), numeric: true),
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
                          DataCell(Text(fmt(r.totals.everyOtherDayDays))),
                          DataCell(Text(fmt(r.totals.longestChain))),
                          DataCell(Text(fmt(r.totals.fatigue))),
                          DataCell(Text(fmt(r.totals.dayShifts))),
                          DataCell(Text(fmt(r.totals.attendedDays))),
                          DataCell(Text(fmt(r.totals.workedHours))),
                          DataCell(Text(fmt(r.totals.overtimeHours))),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          if (summary.rows.any(
            (r) => r.totals.everyOtherDayChains.isNotEmpty,
          )) ...[
            const PillHeader('Gün aşırı nöbetler', end: 'Dokun: ayrıntı'),
            GroupCard(
              children: [
                for (final r in summary.rows)
                  if (r.totals.everyOtherDayChains.isNotEmpty)
                    ListTile(
                      key: ValueKey('chains-${r.personId}'),
                      title: Text(r.name),
                      subtitle: Text(r.totals.chainSummary),
                      trailing: Text(
                        '${r.totals.everyOtherDayDays} gün',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      onTap: () => _showChains(context, _year, summary, r),
                    ),
              ],
            ),
          ],
          if (summary.rows.isNotEmpty) ...[
            const PillHeader('Yorgunluk puanı', end: 'Dokun: döküm'),
            GroupCard(
              children: [
                for (final r in [
                  ...summary.rows,
                ]..sort((a, b) => b.totals.fatigue.compareTo(a.totals.fatigue)))
                  ListTile(
                    key: ValueKey('fatigue-${r.personId}'),
                    title: Text(r.name),
                    subtitle: Text(
                      r.isChargeNurse
                          ? 'Sorumlu hemşire'
                          : 'Rol ortalaması '
                                '${fmt(summary.roleMean(r.role, (t) => t.fatigue))}',
                    ),
                    trailing: Text(
                      fmt(r.totals.fatigue),
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    onTap: () => _showFatigue(context, _year, summary, r),
                  ),
              ],
            ),
          ],
          if (requests.isNotEmpty) ...[
            const PillHeader('İstek karşılanma', end: 'Dokun: ayrıntı'),
            GroupCard(
              children: [
                for (final r in requests)
                  ListTile(
                    key: ValueKey('requests-${r.personId}'),
                    title: Text(r.name),
                    subtitle: Text(r.breakdown),
                    trailing: Text(
                      '%${r.percent}',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: r.percent < 100 ? theme.colorScheme.error : null,
                      ),
                    ),
                    onTap: () => _showRequests(context, _year, r),
                  ),
              ],
            ),
          ],
          if (ref.watch(leaveBalancesProvider(_year)) case final balances
              when balances.isNotEmpty) ...[
            const PillHeader('Yıllık izin bakiyesi', end: 'İş günü'),
            GroupCard(
              children: [
                for (final p in ref.watch(peopleProvider))
                  if (balances[p.id] case final b?)
                    ListTile(
                      key: ValueKey('leave-${p.id}'),
                      title: Text(p.name),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(LeaveBalances.label(b)),
                          const SizedBox(height: 4),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(99),
                            child: LinearProgressIndicator(
                              value: b.allowance == 0
                                  ? 1
                                  : (b.used / b.allowance).clamp(0.0, 1.0),
                              minHeight: 6,
                              color: b.remaining < 0
                                  ? theme.colorScheme.error
                                  : null,
                            ),
                          ),
                        ],
                      ),
                    ),
              ],
            ),
          ],
          if (summary.rows.isNotEmpty) MonthlyComparison(summary: summary),
        ],
      ),
    );
  }
}

/// Yorgunluk puanının dökümü ve aylara göre değeri.
void _showFatigue(
  BuildContext context,
  int year,
  YearlySummary summary,
  YearlyRow row,
) {
  final theme = Theme.of(context);
  String fmt(num v) => SummaryTable.fmt(v);
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.75,
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            Text(
              '${row.name} · $year yorgunluk: ${fmt(row.totals.fatigue)}',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            for (final p in FatigueScore.parts(row.totals))
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(p.label),
                subtitle: Text('${fmt(p.count)} kez'),
                trailing: Text('+${fmt(p.points)}'),
              ),
            const Divider(),
            Text('Aylara göre', style: theme.textTheme.titleSmall),
            Wrap(
              spacing: 12,
              children: [
                for (final m in summary.months)
                  if (row.byMonth[m] case final t?)
                    Text('${turkishMonthNames[m - 1]} ${fmt(t.fatigue)}'),
              ],
            ),
            const SizedBox(height: 8),
            Text(FatigueScore.weights, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    ),
  );
}

/// Kişinin yıl içindeki istekleri: karşılanmayanlar ay ay, sonra döküm.
void _showRequests(BuildContext context, int year, PersonRequests r) {
  final theme = Theme.of(context);
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.75,
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            Text(
              '${r.name} · $year istekleri',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              '${r.total} isteğin ${r.met} tanesi karşılandı (%${r.percent}).',
            ),
            const SizedBox(height: 4),
            Text(r.breakdown, style: theme.textTheme.bodySmall),
            const Divider(),
            if (r.unmet.isEmpty)
              const Text('Bütün istekleri karşılandı.')
            else ...[
              Text('Karşılanmayanlar', style: theme.textTheme.titleSmall),
              for (final i in r.unmet)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    Icons.error_outline,
                    color: theme.colorScheme.error,
                  ),
                  title: Text(
                    '${turkishMonthNames[i.month - 1]} · ${i.kind.label}',
                  ),
                  subtitle: Text(i.detail),
                ),
              if (r.unmet.any((i) => i.kind == RequestKind.overtime))
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Fazla mesai isteği karşılanmayan kişi, sonraki ay yine '
                    'isterse liste oluşturulurken önce ona fazla nöbet '
                    'verilir.',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
            ],
          ],
        ),
      ),
    ),
  );
}

/// Kişinin yıl içindeki gün aşırı zincirleri, ay ay.
void _showChains(
  BuildContext context,
  int year,
  YearlySummary summary,
  YearlyRow row,
) {
  final theme = Theme.of(context);
  final t = row.totals;
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.75,
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            Text(
              '${row.name} · $year gün aşırı',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'Toplam ${t.everyOtherDayDays} gün, '
              '${t.everyOtherDayChains.length} zincir; en uzun '
              '${EveryOtherDayChains.lengthLabel(t.longestChain)}.',
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final e in t.chainCounts.entries)
                  Chip(
                    label: Text(
                      '${EveryOtherDayChains.lengthLabel(e.key)} × ${e.value}',
                    ),
                  ),
              ],
            ),
            const Divider(),
            for (final m in summary.months)
              if (row.byMonth[m]?.everyOtherDayChains case final chains?
                  when chains.isNotEmpty)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(turkishMonthNames[m - 1]),
                  subtitle: Text(
                    [
                      for (final c in chains)
                        '${EveryOtherDayChains.format(c)} '
                            '(${EveryOtherDayChains.lengthLabel(c.length)})',
                    ].join(' · '),
                  ),
                  trailing: Text(
                    '${chains.fold(0, (s, c) => s + c.length)} gün',
                  ),
                ),
          ],
        ),
      ),
    ),
  );
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
    // Koyu zeminde lacivert okunmaz; açık tonu.
    final techColor = theme.brightness == Brightness.dark
        ? const Color(0xFF8C9EFF)
        : _techColor;
    final color = isTech ? techColor : brand.stepper;
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
                            ? techColor.withValues(alpha: 0.14)
                            : brand.pill,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        isTech ? 'Rad. Tek.' : role.label,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: isTech ? techColor : brand.onPill,
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
