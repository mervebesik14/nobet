import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../logic/turkish_collation.dart';
import '../../models/models.dart';
import '../../shared/person_colors.dart';
import '../../shared/widgets/brand_widgets.dart';
import '../people/people_controller.dart';
import 'month_open_providers.dart';

/// Kalıcı istekler: her ay kendiliğinden istenmeyen güne işlenir (ay başı
/// sihirbazında "Kalıcı istekleri işle").
class RecurringRequestsPage extends ConsumerWidget {
  const RecurringRequestsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requests = ref.watch(recurringRequestsProvider);
    final people = ref.watch(peopleProvider);
    final byId = {for (final p in people) p.id: p};
    final sorted =
        [
          for (final r in requests)
            if (byId[r.personId] != null) r,
        ]..sort(
          (a, b) =>
              compareTurkish(byId[a.personId]!.name, byId[b.personId]!.name),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Kalıcı istekler')),
      floatingActionButton: FloatingActionButton.extended(
        key: const ValueKey('recurring-add'),
        heroTag: null,
        onPressed: () => showDialog<void>(
          context: context,
          builder: (_) => _AddDialog(
            people: [
              for (final p in people)
                if (p.isActive || p.inactiveFrom != null) p,
            ]..sort((a, b) => compareTurkish(a.name, b.name)),
          ),
        ),
        icon: const Icon(Icons.add),
        label: const Text('İstek ekle'),
      ),
      body: ListView(
        padding: const EdgeInsets.only(top: 8, bottom: 100),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Text(
              'Bir kez girilir, her ay "Ay başı sihirbazı"nda istenmeyen '
              'güne işlenir. Örn. "her Çarşamba", "hafta sonları", "ayın 1. '
              'günü"; bitiş tarihi verilirse sonrasında işlenmez.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          PillHeader('İstekler', trailing: '${sorted.length}'),
          GroupCard(
            children: [
              if (sorted.isEmpty)
                const ListTile(title: Text('Henüz kalıcı istek yok.')),
              for (final r in sorted)
                ListTile(
                  key: ValueKey('recurring-${r.id}'),
                  leading: PersonAvatar.of(byId[r.personId]!, radius: 16),
                  title: Text(byId[r.personId]!.name),
                  subtitle: Text('Olmaz: ${r.describe()}'),
                  trailing: IconButton(
                    tooltip: 'Sil',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => ref
                        .read(recurringRequestsProvider.notifier)
                        .remove(r.id),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AddDialog extends ConsumerStatefulWidget {
  const _AddDialog({required this.people});

  final List<Person> people;

  @override
  ConsumerState<_AddDialog> createState() => _AddDialogState();
}

class _AddDialogState extends ConsumerState<_AddDialog> {
  String? _personId;
  final _weekdays = <int>{};
  final _days = TextEditingController();
  DateTime? _until;

  static const _short = ['Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz'];

  @override
  void dispose() {
    _days.dispose();
    super.dispose();
  }

  Set<int> get _monthDays => {
    for (final m in RegExp(r'\d+').allMatches(_days.text))
      if (int.parse(m[0]!) case final d when d >= 1 && d <= 31) d,
  };

  @override
  Widget build(BuildContext context) {
    final valid =
        _personId != null && (_weekdays.isNotEmpty || _monthDays.isNotEmpty);
    return AlertDialog(
      title: const Text('Kalıcı istek'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButtonFormField<String>(
              key: const ValueKey('recurring-person'),
              initialValue: _personId,
              decoration: const InputDecoration(labelText: 'Kişi'),
              items: [
                for (final p in widget.people)
                  DropdownMenuItem(value: p.id, child: Text(p.name)),
              ],
              onChanged: (v) => setState(() => _personId = v),
            ),
            const SizedBox(height: 12),
            const Text('Nöbet tutamayacağı günler'),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (var w = 1; w <= 7; w++)
                  FilterChip(
                    key: ValueKey('recurring-wd-$w'),
                    label: Text(_short[w - 1]),
                    selected: _weekdays.contains(w),
                    onSelected: (on) => setState(
                      () => on ? _weekdays.add(w) : _weekdays.remove(w),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              key: const ValueKey('recurring-days'),
              controller: _days,
              keyboardType: TextInputType.text,
              decoration: const InputDecoration(
                labelText: 'Ayın günleri (isteğe bağlı)',
                hintText: 'ör. 1, 15',
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _until == null
                        ? 'Süresiz'
                        : '${DateFormat('d MMMM y', 'tr_TR').format(_until!)} sonuna kadar',
                  ),
                ),
                TextButton(
                  onPressed: () async {
                    final now = DateTime.now();
                    final picked = await showDatePicker(
                      context: context,
                      firstDate: DateTime(now.year - 1),
                      lastDate: DateTime(now.year + 3),
                      initialDate: _until ?? now,
                      locale: const Locale('tr', 'TR'),
                    );
                    if (picked != null) setState(() => _until = picked);
                  },
                  child: const Text('Bitiş seç'),
                ),
                if (_until != null)
                  IconButton(
                    tooltip: 'Bitişi kaldır',
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() => _until = null),
                  ),
              ],
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
          key: const ValueKey('recurring-save'),
          onPressed: !valid
              ? null
              : () async {
                  await ref
                      .read(recurringRequestsProvider.notifier)
                      .add(
                        personId: _personId!,
                        weekdays: {..._weekdays},
                        monthDays: _monthDays,
                        until: _until,
                      );
                  if (context.mounted) Navigator.of(context).pop();
                },
          child: const Text('Ekle'),
        ),
      ],
    );
  }
}
