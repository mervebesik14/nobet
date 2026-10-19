import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../logic/person_totals.dart';
import '../../logic/yearly_summary.dart';
import '../../models/models.dart';
import 'summary_table.dart';

/// Karşılaştırılan ölçü.
enum ComparisonMetric {
  shifts('Nöbet', 'nöbet'),
  weekend('Hafta sonu', 'hafta sonu nöbeti'),
  national('Resmi tatil', 'resmi tatil nöbeti'),
  religious('Dini bayram', 'dini bayram nöbeti'),
  longGaps('4–5 gün ara', '4–5 günlük ara'),
  overtime('Fazla mesai', 'saat fazla mesai');

  const ComparisonMetric(this.label, this.unit);

  final String label;

  /// Hücre açıklamasındaki birim ("9 nöbet").
  final String unit;

  num pick(PersonTotals t) => switch (this) {
    shifts => t.shifts,
    weekend => t.weekendShifts,
    national => t.nationalHolidayShifts,
    religious => t.religiousHolidayShifts,
    longGaps => t.longGaps,
    overtime => t.overtimeHours,
  };
}

/// Yıllık özette kişi × ay tablosu: seçilen ölçünün her ayki değeri.
/// Hücre rengi kişinin o ay aynı roldeki ortalamadan farkını gösterir:
/// kırmızı = ortalamanın üstü, mavi = altı, renksiz = ortalamaya yakın.
/// Değer hücrede yazılıdır (renk tek başına bilgi taşımaz); hücreye
/// dokununca açıklama çıkar.
class MonthlyComparison extends StatefulWidget {
  const MonthlyComparison({super.key, required this.summary});

  final YearlySummary summary;

  @override
  State<MonthlyComparison> createState() => _MonthlyComparisonState();
}

class _MonthlyComparisonState extends State<MonthlyComparison> {
  ComparisonMetric _metric = ComparisonMetric.shifts;

  /// Bu kadar farkın altı "ortalamaya yakın" sayılır (renksiz).
  static const _neutral = 0.5;

  /// Renk bu farkta en koyu olur.
  static const _full = 2.0;

  // Iraksak çift: kırmızı (üstü) ↔ mavi (altı); açık / koyu tema adımları.
  static const _aboveLight = Color(0xFFE34948);
  static const _aboveDark = Color(0xFFE66767);
  static const _belowLight = Color(0xFF2A78D6);
  static const _belowDark = Color(0xFF3987E5);

  Color? _tint(double? deviation, ColorScheme scheme, bool dark) {
    if (deviation == null || deviation.abs() < _neutral) return null;
    final strength = ((deviation.abs() - _neutral) / (_full - _neutral)).clamp(
      0.0,
      1.0,
    );
    final base = deviation > 0
        ? (dark ? _aboveDark : _aboveLight)
        : (dark ? _belowDark : _belowLight);
    return Color.alphaBlend(
      base.withValues(alpha: 0.18 + 0.32 * strength),
      scheme.surface,
    );
  }

  @override
  Widget build(BuildContext context) {
    final summary = widget.summary;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final months = summary.months;
    final monthName = DateFormat.MMM('tr_TR');
    String fmt(num v) => SummaryTable.fmt(v);
    final metric = _metric;

    Widget cell(
      String text, {
      Color? color,
      bool bold = false,
      String? tooltip,
      Key? key,
    }) {
      final child = Container(
        key: key,
        height: 36,
        alignment: Alignment.center,
        margin: const EdgeInsets.all(1),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          text,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: bold ? FontWeight.w600 : null,
          ),
        ),
      );
      return tooltip == null
          ? child
          : Tooltip(
              message: tooltip,
              triggerMode: TooltipTriggerMode.tap,
              child: child,
            );
    }

    Widget nameCell(String text, {bool header = false}) => Container(
      height: 36,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Text(
        text,
        overflow: TextOverflow.ellipsis,
        style: header
            ? theme.textTheme.labelLarge?.copyWith(color: scheme.primary)
            : theme.textTheme.bodyMedium,
      ),
    );

    final rows = <TableRow>[
      TableRow(
        children: [
          nameCell(''),
          for (final m in months)
            cell(monthName.format(DateTime(2000, m)), bold: true),
          cell('Toplam', bold: true),
        ],
      ),
    ];
    Role? currentRole;
    for (final r in summary.rows) {
      if (r.role != currentRole) {
        currentRole = r.role;
        rows.add(
          TableRow(
            children: [
              nameCell(r.role.pluralLabel, header: true),
              for (final _ in months) const SizedBox.shrink(),
              const SizedBox.shrink(),
            ],
          ),
        );
      }
      rows.add(
        TableRow(
          children: [
            nameCell(r.isChargeNurse ? '${r.name} (sorumlu)' : r.name),
            for (final m in months)
              if (r.byMonth[m] case final t?)
                () {
                  final value = metric.pick(t);
                  final dev = r.isChargeNurse
                      ? null
                      : summary.deviation(r, m, metric.pick);
                  final avg = dev == null ? null : value - dev;
                  return cell(
                    fmt(value),
                    key: ValueKey('cmp-${r.personId}-$m'),
                    color: _tint(dev, scheme, dark),
                    tooltip:
                        '${r.name} · ${monthName.format(DateTime(2000, m))}: '
                        '${fmt(value)} ${metric.unit}'
                        '${avg == null ? '' : ' (ortalama ${fmt(avg)})'}',
                  );
                }()
              else
                cell('–'),
            cell(fmt(metric.pick(r.totals)), bold: true),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text('Aylara göre', style: theme.textTheme.titleMedium),
        ),
        // Ölçü seçimi: tek satır, kaydırılabilir.
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              for (final m in ComparisonMetric.values)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(m.label),
                    selected: m == _metric,
                    onSelected: (_) => setState(() => _metric = m),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Table(
            defaultColumnWidth: const FixedColumnWidth(52),
            columnWidths: const {0: FixedColumnWidth(176)},
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            children: rows,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Wrap(
            spacing: 16,
            runSpacing: 4,
            children: [
              _LegendItem(
                color: _tint(_full, scheme, dark)!,
                label: 'Ortalamanın üstünde',
              ),
              _LegendItem(
                color: _tint(-_full, scheme, dark)!,
                label: 'Ortalamanın altında',
              ),
              _LegendItem(
                color: scheme.surface,
                border: scheme.outlineVariant,
                label: 'Ortalamaya yakın',
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: Text(
            'Hücreye dokununca ayrıntı görünür. Renk, kişinin o ay aynı '
            'görevdekilerin ortalamasından farkını gösterir.',
            style: theme.textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.color, required this.label, this.border});

  final Color color;
  final Color? border;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
            border: border == null ? null : Border.all(color: border!),
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: theme.textTheme.bodySmall),
      ],
    );
  }
}
