import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/models.dart';
import '../../shared/widgets/placeholder_view.dart';
import '../../shared/widgets/section_header.dart';
import 'people_controller.dart';
import 'person_delete_dialog.dart';
import 'person_form_page.dart';

/// Kişiler sekmesi: aktif kişiler role göre gruplu, pasifler en altta soluk.
class PeoplePage extends ConsumerWidget {
  const PeoplePage({super.key});

  static void _openForm(BuildContext context, [Person? person]) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PersonFormPage(person: person),
        fullscreenDialog: person == null,
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final people = ref.watch(peopleProvider);
    final active = people.where((p) => p.isActive).toList();
    final inactive = people.where((p) => !p.isActive).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Kişiler')),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Kişi ekle',
        onPressed: () => _openForm(context),
        child: const Icon(Icons.add),
      ),
      body: people.isEmpty
          ? const PlaceholderView(
              icon: Icons.people_outline,
              message:
                  'Henüz kişi eklenmedi.\n'
                  'Sağ alttaki + ile hemşire ve teknikerleri ekleyin.',
            )
          : ListView(
              // FAB son satırı örtmesin.
              padding: const EdgeInsets.only(bottom: 88),
              children: [
                for (final role in Role.values) ...[
                  SectionHeader(
                    title: role.pluralLabel,
                    count: active.where((p) => p.role == role).length,
                  ),
                  for (final person in active.where((p) => p.role == role))
                    _PersonTile(
                      person: person,
                      onTap: () => _openForm(context, person),
                    ),
                ],
                if (inactive.isNotEmpty) ...[
                  SectionHeader(title: 'Pasif', count: inactive.length),
                  for (final person in inactive)
                    _PersonTile(
                      person: person,
                      onTap: () => _openForm(context, person),
                    ),
                ],
              ],
            ),
    );
  }
}

class _PersonTile extends ConsumerWidget {
  const _PersonTile({required this.person, required this.onTap});

  final Person person;
  final VoidCallback onTap;

  /// Yeni mesaj, öncekinin süresini beklemeden görünsün.
  static void _notify(ScaffoldMessengerState messenger, String message) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// Kaydırma onayı. Silinecekse true döner, Dismissible satırı kaldırır.
  /// Pasif yapmada satır listede kalır (Pasif bölümüne geçer), bu yüzden
  /// işlem burada yapılır ve false döner.
  Future<bool> _confirm(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final choice = await askPersonDelete(context, ref, person);
    switch (choice) {
      case PersonDeleteChoice.delete:
        return true;
      case PersonDeleteChoice.deactivate:
        await ref.read(peopleProvider.notifier).deactivate(person.id);
        _notify(messenger, '${person.name} pasif yapıldı.');
        return false;
      case null:
        return false;
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    await ref.read(peopleProvider.notifier).delete(person.id);
    _notify(messenger, '${person.name} silindi.');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final initial = person.name.isEmpty ? '?' : person.name.characters.first;
    final tile = ListTile(
      leading: CircleAvatar(
        backgroundColor: person.colorValue != null
            ? Color(person.colorValue!)
            : theme.colorScheme.primaryContainer,
        child: Text(initial),
      ),
      title: Text(person.name),
      subtitle: !person.isActive
          ? Text('${person.role.label} · pasif')
          : person.isChargeNurse
          ? const Text('Sorumlu hemşire · 7A')
          : null,
      onTap: onTap,
    );

    return Dismissible(
      key: ValueKey(person.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        color: theme.colorScheme.errorContainer,
        child: Icon(
          Icons.delete_outline,
          color: theme.colorScheme.onErrorContainer,
        ),
      ),
      confirmDismiss: (_) => _confirm(context, ref),
      onDismissed: (_) => _delete(context, ref),
      child: person.isActive ? tile : Opacity(opacity: 0.5, child: tile),
    );
  }
}
