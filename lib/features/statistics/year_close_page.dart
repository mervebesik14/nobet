import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../../data/turkish_holidays.dart';
import '../../logic/file_names.dart';
import '../../logic/leave_balance.dart';
import '../../logic/totals_columns.dart';
import '../../logic/year_close.dart';
import '../../logic/yearly_summary.dart';
import '../../shared/platform_services.dart';
import '../../shared/providers.dart';
import '../../shared/widgets/brand_widgets.dart';
import '../../shared/widgets/motion.dart';
import '../../shared/widgets/pdf_preview_page.dart';
import '../holidays/holidays_controller.dart';
import '../people/leave_balance_provider.dart';
import '../people/people_controller.dart';
import '../settings/backup_actions.dart';
import 'person_report_pdf.dart';
import 'statistics_pdf.dart';

/// Yıl kapanışı: yıllık özet, herkesin karnesi, izin bakiyeleri, gelecek
/// yılın bayram planı ve yedek, sırayla. Yapılan adımlar yıl için
/// hatırlanır.
class YearClosePage extends ConsumerStatefulWidget {
  const YearClosePage({super.key, required this.year, required this.summary});

  final int year;
  final YearlySummary summary;

  @override
  ConsumerState<YearClosePage> createState() => _YearClosePageState();
}

class _YearClosePageState extends ConsumerState<YearClosePage> {
  YearStep? _running;

  int get _year => widget.year;

  Set<YearStep> get _done {
    final raw = ref.read(hiveBoxesProvider).meta.get(YearClose.key(_year));
    return raw is List ? YearClose.fromNames(raw) : <YearStep>{};
  }

  Future<void> _mark(YearStep step) async {
    await ref.read(hiveBoxesProvider).meta.put(YearClose.key(_year), [
      for (final s in {..._done, step}) s.name,
    ]);
    if (mounted) setState(() {});
  }

  void _notify(String message) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));

  String _name(String id) =>
      ref.read(peopleProvider).where((p) => p.id == id).firstOrNull?.name ??
      'Silinmiş kişi';

  List<HolidayTurn> get _turns => YearClose.holidayTurns(
    year: _year,
    thisYear: ref.read(holidaysProvider).where((h) => h.date.year == _year),
    nextHolidays: TurkishHolidays.forYear(_year + 1),
    plans: ref.read(monthPlanRepositoryProvider).getAll(),
    name: _name,
  );

  Future<void> _run(YearStep step) async {
    setState(() => _running = step);
    try {
      final ok = switch (step) {
        YearStep.summary => await _summaryPdf(),
        YearStep.reports => await _reports(),
        YearStep.leave => await _leave(),
        YearStep.holidays => await _holidays(),
        YearStep.backup => mounted && await exportBackup(context, ref),
      };
      if (ok) await _mark(step);
    } catch (e) {
      if (mounted) _notify('Hazırlanamadı: $e');
    } finally {
      if (mounted) setState(() => _running = null);
    }
  }

  Future<bool> _summaryPdf() async {
    final fonts = await ref.read(platformServicesProvider).loadPdfFonts();
    final pdf = await buildStatisticsPdf(
      year: _year,
      summary: widget.summary,
      font: fonts.regular,
      boldFont: fonts.bold,
    );
    if (!mounted) return false;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PdfPreviewPage(
          title: '$_year yıllık özet',
          pdf: pdf,
          fileName: 'nobet-istatistik-$_year.pdf',
        ),
      ),
    );
    return true;
  }

  /// Herkesin karnesi ayrı PDF'ler olarak tek paylaşımda; sütunlar karnede
  /// en son seçilenler.
  Future<bool> _reports() async {
    final services = ref.read(platformServicesProvider);
    final fonts = await services.loadPdfFonts();
    final saved = ref.read(hiveBoxesProvider).meta.get('reportCardColumns');
    final columns = saved is List
        ? TotalsColumn.fromNames(saved.cast<String>())
        : {...TotalsColumn.values};
    final files = [
      for (final row in widget.summary.rows)
        (
          bytes: await buildPersonReportPdf(
            columns: columns,
            year: _year,
            row: row,
            summary: widget.summary,
            font: fonts.regular,
            boldFont: fonts.bold,
            createdAt: ref.read(todayProvider),
          ),
          name: 'karne-${fileSlug(row.name)}-$_year.pdf',
          mime: 'application/pdf',
        ),
    ];
    if (files.isEmpty) {
      _notify('Bu yıl listesi olan kimse yok.');
      return false;
    }
    await services.shareFiles(files, subject: '$_year nöbet karneleri');
    return true;
  }

  String _leaveText() {
    final balances = ref.read(leaveBalancesProvider(_year));
    final lines = [
      for (final e in balances.entries)
        '${_name(e.key)}: ${LeaveBalances.label(e.value)}',
    ]..sort();
    return [
      '$_year yıllık izin bakiyeleri',
      if (lines.isEmpty) 'İzin hakkı girilmiş kişi yok.',
      ...lines,
    ].join('\n');
  }

  Future<bool> _leave() => _showText(
    title: 'İzin bakiyeleri',
    text: _leaveText(),
    subject: '$_year izin bakiyeleri',
  );

  Future<bool> _holidays() => _showText(
    title: '${_year + 1} bayram planı',
    text: YearClose.holidayText(_year, _turns),
    subject: '${_year + 1} bayram planı',
  );

  /// Metni gösterir; "Paylaş" ya da "Tamam" adımı bitirir.
  Future<bool> _showText({
    required String title,
    required String text,
    required String subject,
  }) async {
    final share = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(child: Text(text)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Tamam'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.share),
            label: const Text('Paylaş'),
          ),
        ],
      ),
    );
    if (share == null) return false;
    if (share) {
      await ref
          .read(platformServicesProvider)
          .shareText(text, subject: subject);
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final done = _done;
    final next = YearClose.next(done);
    final total = YearStep.values.length;
    final balances = ref.watch(leaveBalancesProvider(_year));
    final turns = _turns;

    String subtitle(YearStep s) => switch (s) {
      YearStep.summary =>
        '${widget.summary.rows.length} kişi · ${widget.summary.months.length} ay',
      YearStep.reports => '${widget.summary.rows.length} karne',
      YearStep.leave =>
        balances.isEmpty
            ? 'İzin hakkı girilmiş kişi yok.'
            : '${balances.length} kişinin bakiyesi',
      YearStep.holidays =>
        turns.isEmpty
            ? s.description
            : '${turns.length} tatil · ${turns.where((t) => t.lastWorkers.isNotEmpty).length} tanesinde bu yıl tutanlar belli',
      YearStep.backup => s.description,
    };

    return Scaffold(
      appBar: AppBar(title: Text('$_year · Yıl kapanışı')),
      body: ListView(
        padding: const EdgeInsets.only(top: 12, bottom: 100),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  next == null
                      ? 'Yıl kapandı. Hepsi tamam.'
                      : '${done.length} / $total adım tamam',
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                    value: done.length / total,
                    minHeight: 8,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          GroupCard(
            children: [
              for (final (i, s) in YearStep.values.indexed)
                ListTile(
                  key: ValueKey('year-${s.name}'),
                  leading: done.contains(s)
                      ? const SuccessTick(size: 30)
                      : CircleAvatar(
                          radius: 15,
                          backgroundColor: s == next
                              ? scheme.primary
                              : scheme.surfaceContainerHigh,
                          foregroundColor: s == next
                              ? scheme.onPrimary
                              : scheme.onSurfaceVariant,
                          child: Text(
                            '${i + 1}',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                  title: Text(s.label),
                  subtitle: Text(subtitle(s)),
                  trailing: TextButton(
                    onPressed: _running == null ? () => _run(s) : null,
                    child: Text(
                      _running == s
                          ? '…'
                          : done.contains(s)
                          ? 'Tekrar'
                          : 'Yap',
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
      floatingActionButton: next == null
          ? null
          : FloatingActionButton.extended(
              key: const ValueKey('year-next'),
              heroTag: null,
              onPressed: _running == null ? () => _run(next) : null,
              icon: const Icon(Icons.play_arrow_rounded),
              label: Text('Sıradaki: ${next.label}'),
            ),
    );
  }
}
