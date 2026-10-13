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

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columnSpacing: 20,
        headingRowHeight: 56,
        columns: const [
          DataColumn(label: Text('Ad')),
          DataColumn(label: Text('Görev')),
          DataColumn(label: Text('Toplam\nnöbet'), numeric: true),
          DataColumn(label: Text('Hafta sonu\nnöbet'), numeric: true),
          DataColumn(label: Text('Gün aşırı\nçift'), numeric: true),
          DataColumn(label: Text('Çalışılan\nsaat'), numeric: true),
          DataColumn(label: Text('Gereken\nsaat'), numeric: true),
          DataColumn(label: Text('Fazla\nmesai'), numeric: true),
        ],
        rows: [
          for (final r in summary.people)
            DataRow(
              cells: [
                DataCell(Text(r.name)),
                DataCell(Text(r.role.label)),
                number(r.shifts),
                number(r.weekendShifts),
                number(r.everyOtherDayPairs),
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
                number(a.everyOtherDayPairs, style: averageStyle),
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
