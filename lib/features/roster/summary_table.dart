import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../logic/roster_summary.dart';
import '../../shared/app_colors.dart';

/// Liste sonundaki kişi başı özet tablo ve rol grubu ortalamaları.
class SummaryTable extends StatelessWidget {
  const SummaryTable({super.key, required this.summary});

  final RosterSummary summary;

  static final _number = NumberFormat('#,##0.#', 'tr_TR');

  static String fmt(num value) => _number.format(value);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final averageStyle = TextStyle(
      fontStyle: FontStyle.italic,
      color: theme.colorScheme.primary,
    );

    DataCell number(num value, {TextStyle? style}) =>
        DataCell(Text(fmt(value), style: style));

    final has7A = summary.people.any((r) => r.dayShifts > 0);
    final hasNational = summary.people.any((r) => r.nationalHolidayShifts > 0);
    final hasReligious = summary.people.any(
      (r) => r.religiousHolidayShifts > 0,
    );

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columnSpacing: 20,
        headingRowHeight: 56,
        columns: [
          const DataColumn(label: Text('Ad')),
          const DataColumn(label: Text('Görev')),
          const DataColumn(label: Text('Toplam\nnöbet'), numeric: true),
          const DataColumn(label: Text('Hafta sonu\nnöbet'), numeric: true),
          if (hasNational)
            const DataColumn(label: Text('Resmi tatil\nnöbeti'), numeric: true),
          if (hasReligious)
            const DataColumn(label: Text('Dini bayram\nnöbeti'), numeric: true),
          const DataColumn(label: Text('Gün aşırı\nçift'), numeric: true),
          const DataColumn(label: Text('4–5 gün\nara'), numeric: true),
          if (has7A) const DataColumn(label: Text('7A\ngün'), numeric: true),
          const DataColumn(label: Text('Çalışılan\nsaat'), numeric: true),
          const DataColumn(label: Text('Gereken\nsaat'), numeric: true),
          const DataColumn(label: Text('Fazla\nmesai'), numeric: true),
        ],
        rows: [
          for (final r in summary.people)
            DataRow(
              cells: [
                DataCell(Text(r.name)),
                DataCell(
                  Text(r.isChargeNurse ? 'Sorumlu hemşire' : r.role.label),
                ),
                number(r.shifts),
                number(r.weekendShifts),
                if (hasNational) number(r.nationalHolidayShifts),
                if (hasReligious) number(r.religiousHolidayShifts),
                number(r.everyOtherDayPairs),
                number(r.longGaps),
                if (has7A) number(r.dayShifts),
                number(r.workedHours),
                number(r.requiredHours),
                number(r.overtimeHours),
              ],
            ),
          for (final a in summary.averages.values)
            DataRow(
              color: WidgetStatePropertyAll(theme.colorScheme.headerTint),
              cells: [
                DataCell(Text('Ortalama', style: averageStyle)),
                DataCell(Text(a.role.pluralLabel, style: averageStyle)),
                number(a.shifts, style: averageStyle),
                number(a.weekendShifts, style: averageStyle),
                if (hasNational)
                  number(a.nationalHolidayShifts, style: averageStyle),
                if (hasReligious)
                  number(a.religiousHolidayShifts, style: averageStyle),
                number(a.everyOtherDayPairs, style: averageStyle),
                const DataCell(Text('')),
                if (has7A) const DataCell(Text('')),
                number(a.workedHours, style: averageStyle),
                number(summary.requiredHours, style: averageStyle),
                number(a.overtimeHours, style: averageStyle),
              ],
            ),
        ],
      ),
    );
  }
}
