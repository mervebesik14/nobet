import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/models.dart';

/// Seçili aya elle tatil ekleme diyaloğu. Onaylanırsa yeni [Holiday] döner.
class HolidayFormDialog extends StatefulWidget {
  const HolidayFormDialog({
    super.key,
    required this.month,
    required this.takenDays,
  });

  /// Tatilin ekleneceği ay.
  final DateTime month;

  /// Bu ayda zaten tatil kayıtlı günler; listede gösterilmez.
  final Set<int> takenDays;

  @override
  State<HolidayFormDialog> createState() => _HolidayFormDialogState();
}

class _HolidayFormDialogState extends State<HolidayFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  int? _day;
  bool _isHalfDay = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  List<int> get _freeDays {
    final count = DateTime(widget.month.year, widget.month.month + 1, 0).day;
    return [
      for (var d = 1; d <= count; d++)
        if (!widget.takenDays.contains(d)) d,
    ];
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(
      Holiday(
        date: DateTime(widget.month.year, widget.month.month, _day!),
        name: _name.text.trim(),
        isHalfDay: _isHalfDay,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dayFormat = DateFormat('d MMMM EEEE', 'tr_TR');
    return AlertDialog(
      title: const Text('Tatil Ekle'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<int>(
              initialValue: _day,
              decoration: const InputDecoration(labelText: 'Gün'),
              items: [
                for (final d in _freeDays)
                  DropdownMenuItem(
                    value: d,
                    child: Text(
                      dayFormat.format(
                        DateTime(widget.month.year, widget.month.month, d),
                      ),
                    ),
                  ),
              ],
              onChanged: (d) => setState(() => _day = d),
              validator: (d) => d == null ? 'Gün seçin.' : null,
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: 'Ad',
                hintText: 'ör. Köprü izni',
              ),
              textCapitalization: TextCapitalization.sentences,
              validator: (v) =>
                  (v?.trim().isEmpty ?? true) ? 'Ad boş olamaz.' : null,
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Yarım gün (arife)'),
              value: _isHalfDay,
              onChanged: (v) => setState(() => _isHalfDay = v),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Vazgeç'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Ekle')),
      ],
    );
  }
}
