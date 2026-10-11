import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/models.dart';

/// Nöbet tablosu: sütunlar günler, satırlar Hemşire 1..N ve Radyoloji
/// Teknikeri. Tablo yatay kayar, soldaki satır başlıkları sabit kalır.
class RosterTable extends StatelessWidget {
  const RosterTable({
    super.key,
    required this.plan,
    required this.namesById,
    required this.weekendDays,
    required this.holidayDays,
    required this.nursesPerDay,
  });

  final MonthPlan plan;
  final Map<String, String> namesById;
  final Set<int> weekendDays;
  final Set<int> holidayDays;
  final int nursesPerDay;

  static const _labelWidth = 116.0;
  static const _cellWidth = 84.0;
  static const _headerHeight = 48.0;
  static const _rowHeight = 44.0;

  /// "Ayşe Yılmaz" → "Ayşe Y."; tek kelimelik ad olduğu gibi kalır.
  static String shortName(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length < 2) return name;
    return '${parts.first} ${parts.last.characters.first}.';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rows = <(String, String? Function(DayAssignment?))>[
      for (var i = 0; i < nursesPerDay; i++)
        (
          'Hemşire ${i + 1}',
          (a) => (a != null && i < a.nurseIds.length) ? a.nurseIds[i] : null,
        ),
      ('Radyoloji Teknikeri', (a) => a?.techId),
    ];
    final dayFormat = DateFormat.E('tr_TR');
    final border = BorderSide(color: theme.dividerColor);

    Color? columnColor(int day) {
      if (holidayDays.contains(day)) return theme.colorScheme.tertiaryContainer;
      if (weekendDays.contains(day)) {
        return theme.colorScheme.secondaryContainer;
      }
      return null;
    }

    Widget cell({
      required double width,
      required double height,
      required Widget child,
      Color? color,
    }) => Container(
      width: width,
      height: height,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: color,
        border: Border(bottom: border, right: border),
      ),
      child: child,
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            cell(
              width: _labelWidth,
              height: _headerHeight,
              color: theme.colorScheme.surfaceContainerHighest,
              child: const Text('Gün'),
            ),
            for (final (label, _) in rows)
              cell(
                width: _labelWidth,
                height: _rowHeight,
                color: theme.colorScheme.surfaceContainerHighest,
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelMedium,
                ),
              ),
          ],
        ),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Column(
              children: [
                Row(
                  children: [
                    for (var d = 1; d <= plan.daysInMonth; d++)
                      cell(
                        width: _cellWidth,
                        height: _headerHeight,
                        color:
                            columnColor(d) ??
                            theme.colorScheme.surfaceContainerHighest,
                        child: Text(
                          '$d ${dayFormat.format(DateTime(plan.year, plan.month, d))}',
                          style: theme.textTheme.labelLarge,
                        ),
                      ),
                  ],
                ),
                for (final (_, pick) in rows)
                  Row(
                    children: [
                      for (var d = 1; d <= plan.daysInMonth; d++)
                        _assigneeCell(
                          context,
                          pick(plan.assignments[d]),
                          cell,
                          columnColor(d),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _assigneeCell(
    BuildContext context,
    String? id,
    Widget Function({
      required double width,
      required double height,
      required Widget child,
      Color? color,
    })
    cell,
    Color? color,
  ) {
    final theme = Theme.of(context);
    if (id == null) {
      return cell(
        width: _cellWidth,
        height: _rowHeight,
        color: theme.colorScheme.errorContainer,
        child: Text(
          'Eksik',
          style: TextStyle(color: theme.colorScheme.onErrorContainer),
        ),
      );
    }
    return cell(
      width: _cellWidth,
      height: _rowHeight,
      color: color,
      child: Text(
        shortName(namesById[id] ?? 'Silinmiş kişi'),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: theme.textTheme.bodySmall,
      ),
    );
  }
}
