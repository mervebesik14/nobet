import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../logic/day_shift_planner.dart';
import '../../models/models.dart';
import '../../shared/app_colors.dart';

/// Tablodaki bir kişi satırı.
typedef RosterRow = ({String id, String name, Role role});

/// Tablodaki bir hücre: kişi ve gün.
typedef RosterCell = ({String personId, int day});

/// Nöbet tablosu: sütunlar ayın günleri, satırlar kişiler (rol gruplarına
/// ayrılmış). Kişinin nöbetçi olduğu günde nöbet süresi ("24") yazar.
/// Tablo yatay kayar, soldaki isim sütunu sabit kalır. Sayfa aşağı
/// kaydırılırken gün başlıkları (1, 2, … ve gün adı) üstte sabit kalır;
/// başlık ile tablo birlikte yatay kayar. Bir sliver'dır: [CustomScrollView]
/// içinde kullanılır. Hücrelere dokunma ve uzun basma elle düzenleme için
/// dışarı bildirilir; kural ihlali olan hücreler renklenir.
class RosterTable extends StatefulWidget {
  const RosterTable({
    super.key,
    required this.plan,
    required this.rows,
    required this.weekendDays,
    required this.holidayDays,
    required this.shiftHours,
    this.missingByDay = const {},
    this.dayShifts = const [],
    this.violationCells = const {},
    this.selectedCell,
    this.onCellTap,
    this.onCellLongPress,
    this.onMissingTap,
    this.highlightedId,
    this.onNameTap,
  });

  final MonthPlan plan;

  /// Satır sırası; aynı roldekiler art arda gelmeli.
  final List<RosterRow> rows;
  final Set<int> weekendDays;
  final Set<int> holidayDays;
  final int shiftHours;

  /// Gün → boş kalan koltuk sayısı; doluysa en altta "Eksik" satırı çıkar.
  final Map<int, int> missingByDay;

  /// Gün → 7A (gündüz mesaisi) çalışanı; o kişinin hücresinde "7A" yazar.
  final Iterable<DayShift> dayShifts;

  /// Kural ihlali olan hücreler.
  final Set<RosterCell> violationCells;

  /// Takas için seçilmiş hücre.
  final RosterCell? selectedCell;

  final void Function(RosterCell cell)? onCellTap;
  final void Function(RosterCell cell)? onCellLongPress;
  final void Function(int day)? onMissingTap;

  /// Vurgulanan kişi: satırı ve nöbet günlerinin sütunları öne çıkar.
  final String? highlightedId;

  /// İsme dokunulunca (vurgulamak / kaldırmak için).
  final void Function(String personId)? onNameTap;

  static const _labelWidth = 140.0;
  static const _cellWidth = 44.0;
  static const _headerHeight = 56.0;
  static const _rowHeight = 36.0;
  static const _groupHeight = 28.0;

  @override
  State<RosterTable> createState() => _RosterTableState();
}

class _RosterTableState extends State<RosterTable> {
  // Başlık ile gövdenin yatay kaydırması birbirini izler.
  final _header = ScrollController();
  final _body = ScrollController();
  var _syncing = false;

  @override
  void initState() {
    super.initState();
    _header.addListener(() => _follow(_header, _body));
    _body.addListener(() => _follow(_body, _header));
  }

  void _follow(ScrollController from, ScrollController to) {
    if (_syncing || !to.hasClients || !from.hasClients) return;
    if (to.offset == from.offset) return;
    _syncing = true;
    to.jumpTo(from.offset.clamp(0, to.position.maxScrollExtent));
    _syncing = false;
  }

  @override
  void dispose() {
    _header.dispose();
    _body.dispose();
    super.dispose();
  }

  static const _labelWidth = RosterTable._labelWidth;
  static const _cellWidth = RosterTable._cellWidth;
  static const _headerHeight = RosterTable._headerHeight;
  static const _rowHeight = RosterTable._rowHeight;
  static const _groupHeight = RosterTable._groupHeight;

  MonthPlan get plan => widget.plan;
  List<RosterRow> get rows => widget.rows;
  Set<int> get weekendDays => widget.weekendDays;
  Set<int> get holidayDays => widget.holidayDays;
  int get shiftHours => widget.shiftHours;
  Map<int, int> get missingByDay => widget.missingByDay;
  Iterable<DayShift> get dayShifts => widget.dayShifts;
  Set<RosterCell> get violationCells => widget.violationCells;
  RosterCell? get selectedCell => widget.selectedCell;
  void Function(RosterCell cell)? get onCellTap => widget.onCellTap;
  void Function(RosterCell cell)? get onCellLongPress => widget.onCellLongPress;
  void Function(int day)? get onMissingTap => widget.onMissingTap;
  String? get highlightedId => widget.highlightedId;
  void Function(String personId)? get onNameTap => widget.onNameTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dayFormat = DateFormat.E('tr_TR');
    final border = BorderSide(color: theme.dividerColor);
    final days = [for (var d = 1; d <= plan.daysInMonth; d++) d];
    final onDayShift = {for (final s in dayShifts) (s.personId, s.day)};

    // Kişi → nöbet günleri.
    final worked = <String, Set<int>>{};
    for (final a in plan.assignments.values) {
      for (final id in a.personIds) {
        (worked[id] ??= {}).add(a.day);
      }
    }

    // Vurgulanan kişinin nöbet günleri: o sütunlar hafifçe öne çıkar.
    final highlightDays = highlightedId == null
        ? const <int>{}
        : worked[highlightedId] ?? const <int>{};
    final highlightTint = Color.alphaBlend(
      scheme.primary.withValues(alpha: 0.10),
      scheme.surface,
    );

    Color? columnColor(int day) {
      if (highlightDays.contains(day)) return highlightTint;
      if (holidayDays.contains(day)) return scheme.holidayTint;
      if (weekendDays.contains(day)) return scheme.weekendTint;
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
            color: scheme.groupTint,
            alignment: Alignment.centerLeft,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                row.role.pluralLabel,
                maxLines: 1,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: scheme.primary,
                  fontWeight: FontWeight.w600,
                ),
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
                  color: scheme.groupTint,
                ),
            ],
          ),
        );
      }
      final highlighted = row.id == highlightedId;
      left.add(
        _tappable(
          key: ValueKey('name-${row.id}'),
          onTap: onNameTap == null ? null : () => onNameTap!(row.id),
          child: box(
            width: _labelWidth,
            height: _rowHeight,
            alignment: Alignment.centerLeft,
            color: highlighted ? scheme.primaryContainer : null,
            child: Text(
              row.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: highlighted ? FontWeight.w700 : null,
                color: highlighted ? scheme.onPrimaryContainer : null,
              ),
            ),
          ),
        ),
      );
      final personDays = worked[row.id] ?? const <int>{};
      // Gün → o gün geçerli izin türü (ilk eşleşen).
      final leaveOn = <int, LeaveType>{
        for (final type in LeaveType.values.reversed)
          for (final d in plan.leaveOf(row.id, type)) d: type,
      };
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
                  // İzinli gün (o gün nöbeti yoksa) türüne göre gösterilir.
                  leave: personDays.contains(d) ? null : leaveOn[d],
                  label:
                      _labelFor(row.id, d, personDays.contains(d)) ??
                      (onDayShift.contains((row.id, d)) ? '7A' : null),
                  isDayShift:
                      !personDays.contains(d) &&
                      onDayShift.contains((row.id, d)),
                  columnColor: highlighted
                      ? Color.alphaBlend(
                          scheme.primary.withValues(alpha: 0.06),
                          columnColor(d) ?? scheme.surface,
                        )
                      : columnColor(d),
                  strong: highlighted && personDays.contains(d),
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
          color: scheme.dangerTint,
          alignment: Alignment.centerLeft,
          child: Text('Eksik', style: TextStyle(color: scheme.error)),
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
                      ? scheme.dangerTint
                      : columnColor(d),
                  child: missingByDay.containsKey(d)
                      ? Text(
                          '${missingByDay[d]}',
                          style: TextStyle(color: scheme.error),
                        )
                      : null,
                ),
              ),
          ],
        ),
      );
    }

    // Gün başlıkları: sayfa kaydırılırken üstte sabit kalır.
    final header = ColoredBox(
      key: const ValueKey('roster-header'),
      color: scheme.surface,
      child: Row(
        children: [
          box(
            width: _labelWidth,
            height: _headerHeight,
            color: scheme.headerTint,
            alignment: Alignment.centerLeft,
            child: const Text('Ad Soyad'),
          ),
          Expanded(
            child: SingleChildScrollView(
              controller: _header,
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final d in days)
                    box(
                      width: _cellWidth,
                      height: _headerHeight,
                      color: columnColor(d) ?? scheme.headerTint,
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
            ),
          ),
        ],
      ),
    );
    // Başlık yeniden kurulunca (sabitlenip çözülünce) gövdenin konumuna
    // gelsin.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _follow(_body, _header);
    });

    return SliverMainAxisGroup(
      slivers: [
        SliverPersistentHeader(
          pinned: true,
          delegate: _HeaderDelegate(height: _headerHeight, child: header),
        ),
        SliverToBoxAdapter(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(children: left),
              Expanded(
                child: SingleChildScrollView(
                  controller: _body,
                  scrollDirection: Axis.horizontal,
                  child: Column(children: right),
                ),
              ),
            ],
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

  /// Nöbet hücresi yazısı: 16B teknikeri ise "16B", yoksa "24". Nöbet
  /// yoksa null (izin yazısı hücrede ayrıca eklenir).
  String? _labelFor(String id, int day, bool works) {
    if (!works) return null;
    return (plan.assignments[day]?.isSecondaryTech(id) ?? false)
        ? '16B'
        : '$shiftHours';
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
    required String? label,
    required Color? columnColor,
    required LeaveType? leave,
    bool isDayShift = false,
    bool strong = false,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final selected = selectedCell == cell;
    final violated = violationCells.contains(cell);
    // Nöbet yoksa ama izin varsa izin yazısı/rengi gösterilir.
    final leaveTint = leave == null ? null : scheme.leaveBackground(leave);
    final leaveInk = leave == null ? null : scheme.leaveInk(leave);
    final text = label ?? leave?.shortLabel;
    final color = selected || strong
        ? scheme.primary
        : violated
        ? scheme.dangerTint
        : isDayShift
        ? scheme.dayShiftTint
        : leaveTint ?? columnColor;
    final textColor = selected || strong
        ? scheme.onPrimary
        : violated
        ? scheme.error
        : isDayShift
        ? scheme.dayShiftColor
        : leaveInk ?? scheme.primary;
    return box(
      width: _cellWidth,
      height: _rowHeight,
      color: color,
      child: text == null
          ? null
          : FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                text,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: textColor,
                ),
              ),
            ),
    );
  }
}

/// Sabit gün başlığı.
class _HeaderDelegate extends SliverPersistentHeaderDelegate {
  const _HeaderDelegate({required this.height, required this.child});

  final double height;
  final Widget child;

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) => child;

  @override
  bool shouldRebuild(_HeaderDelegate oldDelegate) => true;
}
