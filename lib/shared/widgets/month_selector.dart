import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// "◀ Ekim 2026 ▶" biçiminde ay seçici.
class MonthSelector extends StatelessWidget {
  const MonthSelector({
    super.key,
    required this.month,
    required this.onChanged,
  });

  /// Seçili ay (günü önemsiz).
  final DateTime month;
  final ValueChanged<DateTime> onChanged;

  void _shift(int delta) =>
      onChanged(DateTime(month.year, month.month + delta));

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          tooltip: 'Önceki ay',
          icon: const Icon(Icons.chevron_left),
          onPressed: () => _shift(-1),
        ),
        SizedBox(
          width: 160,
          child: Text(
            DateFormat.yMMMM('tr_TR').format(month),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        IconButton(
          tooltip: 'Sonraki ay',
          icon: const Icon(Icons.chevron_right),
          onPressed: () => _shift(1),
        ),
      ],
    );
  }
}
