import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../../logic/turkish_collation.dart';
import '../../models/models.dart';
import '../../shared/person_colors.dart';
import '../../shared/widgets/brand_widgets.dart';
import '../people/people_controller.dart';

/// Birlikte / ayrı kuralları: iki kişi aynı gün olmasın (kesin) ya da
/// mümkünse aynı gün olsun (tercih). Kıdem kişi formundan seçilir.
class PairRulesPage extends ConsumerWidget {
  const PairRulesPage({super.key});

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final people = [
      for (final p in ref.read(peopleProvider))
        if (p.isActive || p.inactiveFrom != null) p,
    ]..sort((a, b) => compareTurkish(a.name, b.name));
    final rule = await showDialog<PairRule>(
      context: context,
      builder: (_) => _AddRuleDialog(people: people),
    );
    if (rule == null) return;
    final settings = ref.read(rosterSettingsProvider);
    await ref
        .read(rosterSettingsProvider.notifier)
        .update(
          settings.copyWith(
            pairRules: [
              for (final r in settings.pairRules)
                if (!r.samePair(rule)) r,
              rule,
            ],
          ),
        );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(rosterSettingsProvider);
    final people = ref.watch(peopleProvider);
    final byId = {for (final p in people) p.id: p};
    final theme = Theme.of(context);
    final rules = [
      for (final r in settings.pairRules)
        if (byId[r.a] != null && byId[r.b] != null) r,
    ];
    final seniors = [
      for (final p in people)
        if (p.seniority == Seniority.senior && p.isActive) p.name,
    ]..sort(compareTurkish);
    final novices = [
      for (final p in people)
        if (p.seniority == Seniority.novice && p.isActive) p.name,
    ]..sort(compareTurkish);

    Future<void> remove(PairRule rule) => ref
        .read(rosterSettingsProvider.notifier)
        .update(
          settings.copyWith(
            pairRules: [
              for (final r in settings.pairRules)
                if (r != rule) r,
            ],
          ),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Birlikte / ayrı kuralları')),
      floatingActionButton: FloatingActionButton.extended(
        key: const ValueKey('pair-add'),
        heroTag: null,
        onPressed: () => _add(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Kural ekle'),
      ),
      body: ListView(
        padding: const EdgeInsets.only(top: 8, bottom: 100),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Text(
              '"Aynı gün olmasın": liste bu ikisini asla aynı güne yazmaz. '
              '"Mümkünse aynı gün": adalet bozulmadıkça aynı güne yazar. '
              'Elle değiştirirken kural bozulursa uyarı çıkar.',
              style: theme.textTheme.bodySmall,
            ),
          ),
          PillHeader('Çiftler', trailing: '${rules.length}'),
          GroupCard(
            children: [
              if (rules.isEmpty)
                const ListTile(title: Text('Henüz kural yok.')),
              for (final r in rules)
                ListTile(
                  key: ValueKey('pair-${r.a}-${r.b}'),
                  leading: SizedBox(
                    width: 56,
                    child: Stack(
                      children: [
                        PersonAvatar.of(byId[r.a]!, radius: 16),
                        Positioned(
                          left: 22,
                          child: PersonAvatar.of(byId[r.b]!, radius: 16),
                        ),
                      ],
                    ),
                  ),
                  title: Text('${byId[r.a]!.name} · ${byId[r.b]!.name}'),
                  subtitle: Text(
                    r.together ? 'Mümkünse aynı gün' : 'Aynı gün olmasın',
                    style: TextStyle(
                      color: r.together
                          ? theme.colorScheme.primary
                          : theme.colorScheme.error,
                    ),
                  ),
                  trailing: IconButton(
                    tooltip: 'Kuralı sil',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => remove(r),
                  ),
                ),
            ],
          ),
          const PillHeader('Kıdem'),
          GroupCard(
            children: [
              ListTile(
                leading: const Icon(Icons.military_tech_outlined),
                title: Text(
                  novices.isEmpty
                      ? 'Yeni başlayan yok'
                      : 'Yeni başlayan: ${novices.join(', ')}',
                ),
                subtitle: Text(
                  '${seniors.isEmpty ? 'Kıdemli seçilmedi' : 'Kıdemli: ${seniors.join(', ')}'}. '
                  'Yeni başlayanın her nöbetinde yanında aynı görevden bir '
                  'kıdemli olur (günde 2 kişi tutulan görevlerde). Kıdem, '
                  'Kişiler\'de kişinin formundan seçilir.',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AddRuleDialog extends StatefulWidget {
  const _AddRuleDialog({required this.people});

  final List<Person> people;

  @override
  State<_AddRuleDialog> createState() => _AddRuleDialogState();
}

class _AddRuleDialogState extends State<_AddRuleDialog> {
  String? _a;
  String? _b;
  bool _together = false;

  @override
  Widget build(BuildContext context) {
    final byId = {for (final p in widget.people) p.id: p};
    final role = _a == null ? null : byId[_a]!.role;
    return AlertDialog(
      title: const Text('Kural ekle'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<String>(
            key: const ValueKey('pair-a'),
            initialValue: _a,
            decoration: const InputDecoration(labelText: '1. kişi'),
            items: [
              for (final p in widget.people)
                DropdownMenuItem(value: p.id, child: Text(p.name)),
            ],
            onChanged: (v) => setState(() {
              _a = v;
              if (_b != null && byId[_b]!.role != byId[v]!.role) _b = null;
              if (_b == v) _b = null;
            }),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            key: ValueKey('pair-b-$_a'),
            initialValue: _b,
            decoration: const InputDecoration(labelText: '2. kişi'),
            items: [
              for (final p in widget.people)
                if (p.id != _a && (role == null || p.role == role))
                  DropdownMenuItem(value: p.id, child: Text(p.name)),
            ],
            onChanged: (v) => setState(() => _b = v),
          ),
          const SizedBox(height: 16),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('Aynı gün olmasın')),
              ButtonSegment(value: true, label: Text('Mümkünse aynı gün')),
            ],
            selected: {_together},
            onSelectionChanged: (v) => setState(() => _together = v.single),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Vazgeç'),
        ),
        FilledButton(
          key: const ValueKey('pair-save'),
          onPressed: _a == null || _b == null
              ? null
              : () => Navigator.of(
                  context,
                ).pop(PairRule(a: _a!, b: _b!, together: _together)),
          child: const Text('Ekle'),
        ),
      ],
    );
  }
}
