import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../models/models.dart';
import '../../logic/turkish_collation.dart';
import '../../shared/brand.dart';
import '../../shared/providers.dart';
import '../../shared/widgets/brand_widgets.dart';
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
    // Bugün pasif döneminde olanlar Pasif bölümünde; dönemi ilerideyse ya
    // da bitmişse aktiflerde görünür.
    final today = ref.watch(todayProvider);
    final active = people.where((p) => p.isActiveOn(today)).toList();
    final inactive = people.where((p) => !p.isActiveOn(today)).toList();

    final counts = [
      for (final role in Role.values)
        if (active.any((p) => p.role == role))
          '${active.where((p) => p.role == role).length} '
              '${turkishLowerCase(role.label)}',
    ];

    return Scaffold(
      appBar: BrandHeader(
        title: 'Kişiler',
        subtitle: counts.isEmpty
            ? 'Hemşire ve teknikerler'
            : counts.join(' · '),
      ),
      floatingActionButton: FloatingActionButton(
        // Sekmeler birlikte durduğu için kahraman geçişi yok.
        heroTag: null,
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
              padding: const EdgeInsets.only(top: 4, bottom: 96),
              children: [
                for (final role in Role.values) ...[
                  SectionHeader(
                    title: role.pluralLabel,
                    count: active.where((p) => p.role == role).length,
                  ),
                  GroupCard(
                    dividerIndent: 72,
                    children: [
                      for (final person in active.where((p) => p.role == role))
                        _PersonTile(
                          person: person,
                          onTap: () => _openForm(context, person),
                        ),
                    ],
                  ),
                ],
                if (inactive.isNotEmpty) ...[
                  SectionHeader(title: 'Pasif', count: inactive.length),
                  GroupCard(
                    dividerIndent: 72,
                    children: [
                      for (final person in inactive)
                        _PersonTile(
                          person: person,
                          onTap: () => _openForm(context, person),
                        ),
                    ],
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
    final choice = await askPersonDelete(context, ref, person);
    switch (choice) {
      case PersonDeleteChoice.delete:
        return true;
      case PersonDeleteChoice.deactivate:
        if (context.mounted) await deactivateWithDate(context, ref, person);
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
    final today = ref.watch(todayProvider);
    final activeNow = person.isActiveOn(today);
    final from = person.inactiveFrom;
    // Pasif dönemi (bitmemişse) her durumda yazılır.
    final period = from == null || person.hasEndedInactivity(today)
        ? null
        : '${person.role.label} · pasif: '
              '${inactivePeriodText(from, person.inactiveUntil)}';
    final brand = context.brand;
    final tile = ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: CircleAvatar(
        radius: 22,
        backgroundColor: person.colorValue != null
            ? Color(person.colorValue!)
            : brand.pill,
        foregroundColor: brand.onPill,
        child: Text(
          initial,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      title: Text(person.name),
      subtitle: period != null
          ? Text(period)
          : person.startDate != null && person.startDate!.isAfter(today)
          ? Text(
              '${person.role.label} · '
              '${DateFormat('d MMMM y', 'tr_TR').format(person.startDate!)} '
              'tarihinde başlıyor',
            )
          : !activeNow
          ? Text('${person.role.label} · pasif')
          : person.isChargeNurse
          ? const Text('Sorumlu hemşire · 7A')
          : null,
      trailing: hasOpenInactivity(person, today)
          ? IconButton(
              tooltip: 'Pasif dönemi sonlandır',
              icon: const Icon(Icons.restart_alt),
              onPressed: () => endInactivityWithDate(context, ref, person),
            )
          : person.isChargeNurse
          ? const _Tag('Sorumlu')
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
      child: activeNow ? tile : Opacity(opacity: 0.5, child: tile),
    );
  }
}

/// Satır sonundaki küçük nane etiket ("Sorumlu").
class _Tag extends StatelessWidget {
  const _Tag(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: brand.pill,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: brand.onPill,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
