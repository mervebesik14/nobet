import 'package:flutter/material.dart';

import '../../logic/text_edits.dart';
import '../../models/models.dart';

/// Yazarak düzenleme: komutlar yazılır, altında anlaşılanlar (ve hatalar)
/// canlı görünür; "Uygula" anlaşılan komutları döndürür.
class TextEditPage extends StatefulWidget {
  const TextEditPage({
    super.key,
    required this.plan,
    required this.people,
    required this.codes,
  });

  final MonthPlan plan;
  final List<Person> people;

  /// Tanımlı özel mesai adları.
  final List<String> codes;

  @override
  State<TextEditPage> createState() => _TextEditPageState();
}

class _TextEditPageState extends State<TextEditPage> {
  final _text = TextEditingController();
  List<TextEditLine> _lines = const [];

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _parse(String text) => setState(
    () => _lines = TextEdits.parse(
      text: text,
      people: widget.people,
      daysInMonth: widget.plan.daysInMonth,
      codes: widget.codes,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final edits = [for (final l in _lines) ?l.edit];
    return Scaffold(
      appBar: AppBar(title: const Text('Yazarak düzenle')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: [
          TextField(
            key: const ValueKey('text-edit-input'),
            controller: _text,
            autofocus: true,
            minLines: 3,
            maxLines: 8,
            onChanged: _parse,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Her satıra bir değişiklik',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 8),
          Text('Örnekler', style: theme.textTheme.titleSmall),
          for (final e in TextEdits.examples)
            Text('• $e', style: theme.textTheme.bodySmall),
          if (_lines.isNotEmpty) ...[
            const Divider(height: 24),
            Text('Anlaşılan', style: theme.textTheme.titleSmall),
            for (final l in _lines)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  l.edit != null ? Icons.check_circle : Icons.error_outline,
                  color: l.edit != null
                      ? theme.colorScheme.primary
                      : theme.colorScheme.error,
                ),
                title: Text(l.edit?.describe(widget.plan.month) ?? l.text),
                subtitle: l.error == null ? null : Text(l.error!),
              ),
          ],
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const ValueKey('text-edit-apply'),
        heroTag: null,
        onPressed: edits.isEmpty
            ? null
            : () => Navigator.of(context).pop(edits),
        icon: const Icon(Icons.done_all),
        label: Text(
          edits.isEmpty ? 'Uygula' : '${edits.length} değişikliği uygula',
        ),
      ),
    );
  }
}
