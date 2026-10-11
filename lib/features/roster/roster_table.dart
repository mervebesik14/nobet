import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/models.dart';

/// Tablodaki bir kişi satırı.
typedef RosterRow = ({String id, String name, Role role});

/// Tablodaki bir hücre: kişi ve gün.
typedef RosterCell = ({String personId, int day});

/// Nöbet tablosu: sütunlar ayın günleri, satırlar kişiler (rol gruplarına
/// ayrılmış). Kişinin nöbetçi olduğu günde nöbet süresi ("24") yazar.
/// Tablo yatay kayar, soldaki isim sütunu sabit kalır. Hücrelere dokunma ve
/// uzun basma elle düzenleme için dışarı bildirilir; kural ihlali olan
/// hücreler renklenir.
class RosterTable extends StatelessWidget {
  const RosterTable({
    super.key,
    required this.plan,
    required this.rows,
    required this.weekendDays,
    required this.holidayDays,
    required this.shiftHours,
    this.missingByDay = const {},
    this.violationCells = const {},
    this.selectedCell,
    this.onCellTap,
    this.onCellLongPress,
    this.onMissingTap,
  });

  final MonthPlan plan;

  /// Satır sırası; aynı roldekiler art arda gelmeli.
  final List<RosterRow> rows;
  final Set<int> weekendDays;
  final Set<int> holidayDays;
  final int shiftHours;

  /// Gün → boş kalan koltuk sayısı; doluysa en altta "Eksik" satırı çıkar.
  final Map<int, int> missingByDay;

  /// Kural ihlali olan hücreler.
  final Set<RosterCell> violationCells;

  /// Takas için seçilmiş hücre.
  final RosterCell? selectedCell;

  final void Function(RosterCell cell)? onCellTap;
  final void Function(RosterCell cell)? onCellLongPress;
  final void Function(int day)? onMissingTap;

  static const _labelWidth = 140.0;
  static const _cellWidth = 44.0;
  static const _headerHeight = 56.0;
  static const _rowHeight = 36.0;
  static const _groupHeight = 28.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dayFormat = DateFormat.E('tr_TR');
    final border = BorderSide(color: theme.dividerColor);
    final days = [for (var d = 1; d <= plan.daysInMonth; d++) d];

    // Kişi → nöbet günleri.
    final worked = <String, Set<int>>{};
    for (final a in plan.assignments.values) {
      for (final id in a.personIds) {
        (worked[id] ??= {}).add(a.day);
      }
    }

    Color? columnColor(int day) {
      if (holidayDays.contains(day)) return scheme.tertiaryContainer;
      if (weekendDays.contains(day)) return scheme.secondaryContainer;
      return null;
    }

    Widget box({
      required double width,
      required double height,
      Widget? child,
      Color? color,
      Alignment alignment = Alignment.center,
    }) => Container(
      width: width,
      height: height,
      alignment: alignment,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: color,
        border: Border(bottom: border, right: border),
      ),
      child: child,
    );

    // Satırlar: rol değişiminde grup başlığı, ardından kişiler.
    final left = <Widget>[];
    final right = <Widget>[];
    Role? currentRole;
    for (final row in rows) {
      if (row.role != currentRole) {
        currentRole = row.role;
        left.add(
          box(
            width: _labelWidth,
            height: _groupHeight,
            color: scheme.primaryContainer,
            alignment: Alignment.centerLeft,
            child: Text(
              row.role.pluralLabel,
              style: theme.textTheme.labelMedium?.copyWith(
                color: scheme.onPrimaryContainer,
              ),
            ),
          ),
        );
        right.add(
          Row(
            children: [
              for (final _ in days)
                box(
                  width: _cellWidth,
                  height: _groupHeight,
                  color: scheme.primaryContainer,
                ),
            ],
          ),
        );
      }
      left.add(
        box(
          width: _labelWidth,
          height: _rowHeight,
          alignment: Alignment.centerLeft,
          child: Text(
            row.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium,
          ),
        ),
      );
      final personDays = worked[row.id] ?? const <int>{};
      right.add(
        Row(
          children: [
            for (final d in days)
              _tappable(
                key: ValueKey('cell-${row.id}-$d'),
                onTap: onCellTap == null
                    ? null
                    : () => onCellTap!((personId: row.id, day: d)),
                onLongPress: onCellLongPress == null
                    ? null
                    : () => onCellLongPress!((personId: row.id, day: d)),
                child: _personCell(
                  context,
                  box: box,
                  cell: (personId: row.id, day: d),
                  works: personDays.contains(d),
                  columnColor: columnColor(d),
                ),
              ),
          ],
        ),
      );
    }

    if (missingByDay.isNotEmpty) {
      left.add(
        box(
          width: _labelWidth,
          height: _rowHeight,
          color: scheme.errorContainer,
          alignment: Alignment.centerLeft,
          child: Text(
            'Eksik',
            style: TextStyle(color: scheme.onErrorContainer),
          ),
        ),
      );
      right.add(
        Row(
          children: [
            for (final d in days)
              _tappable(
                key: ValueKey('missing-$d'),
                onTap: missingByDay.containsKey(d) && onMissingTap != null
                    ? () => onMissingTap!(d)
                    : null,
                child: box(
                  width: _cellWidth,
                  height: _rowHeight,
                  color: missingByDay.containsKey(d)
                      ? scheme.errorContainer
                      : columnColor(d),
                  child: missingByDay.containsKey(d)
                      ? Text(
                          '${missingByDay[d]}',
                          style: TextStyle(color: scheme.onErrorContainer),
                        )
                      : null,
                ),
              ),
          ],
        ),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            box(
              width: _labelWidth,
              height: _headerHeight,
              color: scheme.surfaceContainerHighest,
              alignment: Alignment.centerLeft,
              child: const Text('Ad Soyad'),
            ),
            ...left,
          ],
        ),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Column(
              children: [
                Row(
                  children: [
                    for (final d in days)
                      box(
                        width: _cellWidth,
                        height: _headerHeight,
                        color: columnColor(d) ?? scheme.surfaceContainerHighest,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text('$d', style: theme.textTheme.labelLarge),
                              Text(
                                dayFormat.format(
                                  DateTime(plan.year, plan.month, d),
                                ),
                                style: theme.textTheme.labelSmall,
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
                ...right,
              ],
            ),
          ),
        ),
      ],
    );
  }

  static Widget _tappable({
    required Key key,
    required Widget child,
    VoidCallback? onTap,
    VoidCallback? onLongPress,
  }) {
    if (onTap == null && onLongPress == null) {
      return KeyedSubtree(key: key, child: child);
    }
    return InkWell(
      key: key,
      onTap: onTap,
      onLongPress: onLongPress,
      child: child,
    );
  }

  Widget _personCell(
    BuildContext context, {
    required Widget Function({
      required double width,
      required double height,
      Widget? child,
      Color? color,
      Alignment alignment,
    })
    box,
    required RosterCell cell,
    required bool works,
    required Color? columnColor,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final selected = selectedCell == cell;
    final violated = violationCells.contains(cell);
    final color = selected
        ? scheme.primary
        : violated
        ? scheme.errorContainer
        : columnColor;
    final textColor = selected
        ? scheme.onPrimary
        : violated
        ? scheme.onErrorContainer
        : scheme.primary;
    return box(
      width: _cellWidth,
      height: _rowHeight,
      color: color,
      child: works
          ? Text(
              '$shiftHours',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: textColor,
              ),
            )
          : null,
    );
  }
}
