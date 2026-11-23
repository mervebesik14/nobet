import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../logic/quick_search.dart';
import '../../logic/roster_generator.dart';
import '../../logic/turkish_dates.dart';
import '../../shared/person_colors.dart';
import '../../shared/providers.dart';
import '../../shared/widgets/brand_widgets.dart';
import '../holidays/holidays_controller.dart';
import '../people/people_controller.dart';
import '../roster/person_calendar_page.dart';
import 'month_plan_controller.dart';

/// Hızlı arama: "Ayşe", "12", "yarın", "Banu hafta sonu"; seçili ayın
/// listesinde kişinin nöbetleri/izinleri ya da günün nöbetçileri.
class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key});

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  final _query = TextEditingController();

  static const _examples = ['bugün', 'yarın', 'hafta sonu', '15'];

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final plan = ref.watch(monthPlanProvider);
    final people = ref.watch(peopleProvider);
    final byId = {for (final p in people) p.id: p};
    final results = QuickSearch.run(
      query: _query.text,
      plan: plan,
      people: people,
      today: ref.watch(todayProvider),
      weekendDays: RosterGenerator.weekendDays(
        plan.year,
        plan.month,
        ref.watch(holidaysProvider),
        ref.watch(effectiveSettingsProvider),
      ),
      dayShifts: ref.watch(allDayShiftsProvider),
    );
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text('Ara · ${turkishMonthNames[plan.month - 1]} ${plan.year}'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(0, 12, 0, 32),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              key: const ValueKey('search-field'),
              controller: _query,
              autofocus: true,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: 'Ayşe, 12, yarın, Banu hafta sonu…',
                border: const OutlineInputBorder(),
                suffixIcon: _query.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Temizle',
                        icon: const Icon(Icons.close),
                        onPressed: () => setState(_query.clear),
                      ),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          if (_query.text.trim().isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Wrap(
                spacing: 8,
                children: [
                  for (final e in _examples)
                    ActionChip(
                      label: Text(e),
                      onPressed: () => setState(() => _query.text = e),
                    ),
                ],
              ),
            )
          else if (results.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Sonuç yok. Kişi adı, gün numarası, "bugün", "yarın" ya da '
                '"hafta sonu" yazabilirsin.',
                textAlign: TextAlign.center,
              ),
            )
          else
            GroupCard(
              children: [
                for (final r in results)
                  ListTile(
                    key: ValueKey('result-${r.personId ?? 'day'}-${r.day}'),
                    leading: r.personId != null && byId[r.personId] != null
                        ? PersonAvatar.of(byId[r.personId]!, radius: 18)
                        : CircleAvatar(
                            radius: 18,
                            child: Text(
                              '${r.day ?? ''}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                    title: Text(r.title, style: theme.textTheme.titleSmall),
                    subtitle: Text(r.lines.join('\n')),
                    trailing: r.personId == null || !plan.hasRoster
                        ? null
                        : const Icon(Icons.chevron_right),
                    onTap: r.personId == null || !plan.hasRoster
                        ? null
                        : () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => PersonCalendarPage(
                                initialPersonId: r.personId,
                              ),
                            ),
                          ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
