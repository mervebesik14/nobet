import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../models/models.dart';
import '../../shared/providers.dart';
import 'people_controller.dart';
import 'person_delete_dialog.dart';

/// Kişi ekleme ve düzenleme formu. [person] boşsa yeni kişi eklenir.
class PersonFormPage extends ConsumerStatefulWidget {
  const PersonFormPage({super.key, this.person});

  final Person? person;

  @override
  ConsumerState<PersonFormPage> createState() => _PersonFormPageState();
}

class _PersonFormPageState extends ConsumerState<PersonFormPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late Role _role;
  late bool _isActive;
  late bool _isChargeNurse;

  /// Pasif başlangıç günü (Aktif kapalıyken).
  DateTime? _inactiveFrom;
  late final bool _roleLocked;
  bool _saving = false;

  bool get _isEditing => widget.person != null;

  /// Bu kişi dışında işaretli sorumlu hemşire.
  Person? get _otherChargeNurse {
    for (final p in ref.read(peopleProvider)) {
      if (p.isChargeNurse && p.id != widget.person?.id) return p;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    final person = widget.person;
    _name = TextEditingController(text: person?.name ?? '');
    _role = person?.role ?? Role.nurse;
    _isActive = person?.isActive ?? true;
    _isChargeNurse = person?.isChargeNurse ?? false;
    _inactiveFrom = person?.inactiveFrom;
    // Geçmiş listelerde geçen kişinin görevi değişirse o listeler bozulur.
    _roleLocked =
        person != null &&
        ref.read(peopleProvider.notifier).isReferenced(person.id);
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  String? _validateName(String? value) {
    final name = value?.trim() ?? '';
    if (name.isEmpty) return 'Ad boş olamaz.';
    if (ref
        .read(peopleProvider.notifier)
        .isNameTaken(name, exceptId: widget.person?.id)) {
      return 'Bu adla bir kişi zaten var.';
    }
    return null;
  }

  Future<void> _save() async {
    if (_saving || !_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final controller = ref.read(peopleProvider.notifier);
    final person = widget.person;
    final chargeNurse = _role == Role.nurse && _isChargeNurse;
    if (person == null) {
      await controller.add(
        name: _name.text,
        role: _role,
        isActive: _isActive,
        isChargeNurse: chargeNurse,
      );
    } else {
      final messenger = ScaffoldMessenger.of(context);
      await controller.update(
        person.copyWith(
          name: _name.text,
          role: _role,
          isChargeNurse: chargeNurse,
        ),
      );
      final from = _inactiveFrom;
      if (!_isActive &&
          from != null &&
          (person.isActive || person.inactiveFrom != from)) {
        // Pasife alındı ya da pasif başlangıcı değişti: listeler onarılır.
        final report = await controller.deactivate(person.id, from: from);
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(
                deactivationMessage(_name.text.trim(), from, report),
              ),
            ),
          );
      } else if (!_isActive && person.isActive) {
        await controller.deactivate(person.id);
      } else if (_isActive && !person.isActive) {
        await controller.activate(person.id);
      }
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final person = widget.person!;
    final messenger = ScaffoldMessenger.of(context);
    final choice = await askPersonDelete(context, ref, person);
    if (choice == null || !mounted) return;
    if (choice == PersonDeleteChoice.deactivate) {
      if (await deactivateWithDate(context, ref, person) && mounted) {
        Navigator.of(context).pop();
      }
      return;
    }
    await ref.read(peopleProvider.notifier).delete(person.id);
    if (!mounted) return;
    Navigator.of(context).pop();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('${person.name} silindi.')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? 'Kişiyi Düzenle' : 'Yeni Kişi')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _name,
              autofocus: !_isEditing,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                labelText: 'Ad Soyad',
                border: OutlineInputBorder(),
              ),
              validator: _validateName,
              onFieldSubmitted: (_) => _save(),
            ),
            const SizedBox(height: 24),
            Text('Görev', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            SegmentedButton<Role>(
              segments: [
                for (final role in Role.values)
                  ButtonSegment(value: role, label: Text(role.label)),
              ],
              selected: {_role},
              onSelectionChanged: _roleLocked
                  ? null
                  : (selection) => setState(() => _role = selection.single),
            ),
            if (_roleLocked)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Kayıtlı ay planlarında geçtiği için görevi değiştirilemez.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            const SizedBox(height: 16),
            if (_role == Role.nurse)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                secondary: const Icon(Icons.badge_outlined),
                title: const Text('Sorumlu hemşire'),
                subtitle: Text(
                  'Mesai günlerinde 7A çalışır; 24 nöbete yalnızca Ay '
                  'Planı\'nda seçtiği günlerde yazılır.'
                  '${_otherChargeNurse == null ? '' : ' Şu an sorumlu hemşire: ${_otherChargeNurse!.name}; bu kişi seçilirse onunki kalkar.'}',
                ),
                value: _isChargeNurse,
                onChanged: (value) => setState(() => _isChargeNurse = value),
              ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Aktif'),
              subtitle: const Text(
                'Pasif kişilere yeni nöbet verilmez, geçmiş listelerde kalır.',
              ),
              value: _isActive,
              onChanged: (value) => setState(() {
                _isActive = value;
                // Pasife alınırken varsayılan başlangıç bugündür.
                if (!value) _inactiveFrom ??= ref.read(todayProvider);
              }),
            ),
            if (!_isActive && _isEditing && _inactiveFrom != null)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event_busy_outlined),
                title: const Text('Pasif başlangıcı'),
                subtitle: Text(
                  '${DateFormat('d MMMM y EEEE', 'tr_TR').format(_inactiveFrom!)}. '
                  'Bu günden önceki nöbetleri kalır; sonrakiler başkalarına '
                  'verilir.',
                ),
                trailing: TextButton(
                  onPressed: () async {
                    final picked = await pickInactiveFrom(
                      context,
                      _inactiveFrom!,
                    );
                    if (picked != null) setState(() => _inactiveFrom = picked);
                  },
                  child: const Text('Değiştir'),
                ),
              ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.check),
              label: const Text('Kaydet'),
            ),
            if (_isEditing) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                ),
                onPressed: _saving ? null : _delete,
                icon: const Icon(Icons.delete_outline),
                label: const Text('Kişiyi sil'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
