import 'package:flutter/material.dart';

/// İşaretli kutularla sütun seçimi; seçilenleri döner (vazgeçilirse null).
/// En az bir sütun seçilmeden onaylanamaz.
class ColumnPickerDialog<T> extends StatefulWidget {
  const ColumnPickerDialog({
    super.key,
    required this.title,
    required this.intro,
    required this.options,
    required this.initial,
    this.confirmLabel = 'Paylaş',
  });

  final String title;
  final String intro;

  /// (değer, etiket) çiftleri, gösterim sırasıyla.
  final List<(T, String)> options;
  final Set<T> initial;
  final String confirmLabel;

  @override
  State<ColumnPickerDialog<T>> createState() => _ColumnPickerDialogState<T>();
}

class _ColumnPickerDialogState<T> extends State<ColumnPickerDialog<T>> {
  late final _selected = {...widget.initial};

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    contentPadding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              widget.intro,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          for (final (value, label) in widget.options)
            CheckboxListTile(
              key: ValueKey('pick-$value'),
              dense: true,
              value: _selected.contains(value),
              title: Text(label),
              onChanged: (v) => setState(
                () => v! ? _selected.add(value) : _selected.remove(value),
              ),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Vazgeç'),
      ),
      FilledButton(
        key: const ValueKey('pick-confirm'),
        onPressed: _selected.isEmpty
            ? null
            : () => Navigator.of(context).pop({..._selected}),
        child: Text(widget.confirmLabel),
      ),
    ],
  );
}
