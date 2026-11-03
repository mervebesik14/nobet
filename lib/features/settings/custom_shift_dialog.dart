import 'package:flutter/material.dart';

import '../../logic/custom_shift_rules.dart';
import '../../models/models.dart';

/// Özel mesai tanımla / düzenle penceresi. Kaydedilince yeni tanım,
/// "Sil" ile [CustomShiftDialog.deleted] döner; vazgeçilirse null.
class CustomShiftDialog extends StatefulWidget {
  const CustomShiftDialog({super.key, this.initial, required this.others});

  /// Düzenlenen tanım; yeni tanımda null. Ad sonradan değişmez (listedeki
  /// eski kayıtlar bu adla tutulur).
  final CustomShift? initial;

  /// Öteki tanımlar (ad çakışması için).
  final List<CustomShift> others;

  /// "Sil" seçildiğinde dönen işaret.
  static const deleted = CustomShift(code: '', hours: 0);

  @override
  State<CustomShiftDialog> createState() => _CustomShiftDialogState();
}

class _CustomShiftDialogState extends State<CustomShiftDialog> {
  late final _code = TextEditingController(text: widget.initial?.code ?? '');
  late final _hours = TextEditingController(
    text: widget.initial == null
        ? ''
        : '${widget.initial!.hours}'
              .replaceAll(RegExp(r'\.0$'), '')
              .replaceAll('.', ','),
  );
  late int _start = widget.initial?.startMinute ?? 8 * 60;
  late bool _fillsSeat = widget.initial?.fillsSeat ?? true;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    _hours.dispose();
    super.dispose();
  }

  String get _startLabel =>
      CustomShift(code: '', startMinute: _start, hours: 0).startLabel;

  Future<void> _pickStart() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _start ~/ 60, minute: _start % 60),
      helpText: 'Başlangıç saati',
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() => _start = picked.hour * 60 + picked.minute);
    }
  }

  void _save() {
    final hours = CustomShiftRules.parseHours(_hours.text);
    final code = widget.initial?.code ?? CustomShift.normalize(_code.text);
    final error = CustomShiftRules.error(
      code: code,
      hours: hours,
      existing: widget.others,
    );
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.of(context).pop(
      CustomShift(
        code: code,
        startMinute: _start,
        hours: hours!,
        fillsSeat: _fillsSeat,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.initial != null;
    return AlertDialog(
      title: Text(editing ? '${widget.initial!.code} mesaisi' : 'Yeni mesai'),
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const ValueKey('custom-shift-code'),
            controller: _code,
            enabled: !editing,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(
              labelText: 'Mesai adı',
              hintText: 'ör. 19A',
              helperText: editing ? 'Ad değiştirilemez.' : 'Listede görünür.',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('custom-shift-hours'),
            controller: _hours,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Çalışma süresi',
              suffixText: 'saat',
              hintText: 'ör. 19',
            ),
          ),
          const SizedBox(height: 4),
          ListTile(
            key: const ValueKey('custom-shift-start'),
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.schedule),
            title: const Text('Başlangıç saati'),
            trailing: Text(
              _startLabel,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            onTap: _pickStart,
          ),
          SwitchListTile(
            key: const ValueKey('custom-shift-seat'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Nöbet koltuğunu doldurur'),
            subtitle: Text(
              _fillsSeat
                  ? 'O günün nöbetçisi sayılır (16A gibi); ertesi gün nöbet '
                        'yazılmaz.'
                  : 'Ek mesai (7A gibi); koltuk doldurmaz, kurallara girmez, '
                        'yalnız saati eklenir.',
            ),
            value: _fillsSeat,
            onChanged: (v) => setState(() => _fillsSeat = v),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
        ],
      ),
      actions: [
        if (editing)
          TextButton(
            onPressed: () =>
                Navigator.of(context).pop(CustomShiftDialog.deleted),
            child: const Text('Sil'),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Vazgeç'),
        ),
        FilledButton(onPressed: _save, child: const Text('Kaydet')),
      ],
    );
  }
}
