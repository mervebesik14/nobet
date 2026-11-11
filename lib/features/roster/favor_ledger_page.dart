import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../logic/favor_ledger.dart';
import '../../shared/person_colors.dart';
import '../../shared/platform_services.dart';
import '../../shared/widgets/brand_widgets.dart';
import '../month/month_plan_controller.dart';
import '../people/people_controller.dart';

/// İyilik defteri: yıl içinde kim kimin yerine geçti, kim kime kaç nöbet
/// borçlu. Yedek ve takas önerilerinde borçlu olan önce gelir.
class FavorLedgerPage extends ConsumerWidget {
  const FavorLedgerPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plan = ref.watch(monthPlanProvider);
    final ledger = ref.watch(favorLedgerProvider);
    final people = {for (final p in ref.watch(peopleProvider)) p.id: p};
    String name(String id) => people[id]?.name ?? 'Silinmiş kişi';
    final theme = Theme.of(context);

    Widget avatar(String id) => people[id] == null
        ? const CircleAvatar(radius: 16, child: Icon(Icons.person, size: 18))
        : PersonAvatar.of(people[id]!, radius: 16);

    return Scaffold(
      appBar: AppBar(
        title: Text('İyilik defteri · ${plan.year}'),
        actions: [
          IconButton(
            tooltip: 'Paylaş',
            icon: const Icon(Icons.share),
            onPressed: () => ref
                .read(platformServicesProvider)
                .shareText(
                  ledger.text(plan.year, name),
                  subject: '${plan.year} iyilik defteri',
                ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(top: 8, bottom: 24),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Text(
              'Listede "X yerine Y" yapılan değişikliklerden çıkarılır; '
              'karşılıklı takaslar sayılmaz. Y sonra X\'in yerine geçerse borç '
              'kapanır. Biri gelemediğinde yedek ve takas önerilerinde ona '
              'borcu olan önce gelir.',
              style: theme.textTheme.bodySmall,
            ),
          ),
          if (ledger.debts.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Bu yıl açık iyilik borcu yok.',
                textAlign: TextAlign.center,
              ),
            )
          else ...[
            PillHeader('Açık borçlar', trailing: '${ledger.debts.length}'),
            GroupCard(
              children: [
                for (final d in ledger.debts)
                  ExpansionTile(
                    key: ValueKey('favor-${d.debtor}-${d.creditor}'),
                    shape: const Border(),
                    leading: SizedBox(
                      width: 56,
                      child: Stack(
                        children: [
                          avatar(d.debtor),
                          Positioned(left: 22, child: avatar(d.creditor)),
                        ],
                      ),
                    ),
                    title: Text('${name(d.debtor)} → ${name(d.creditor)}'),
                    subtitle: Text(
                      'Yerine geçen: ${name(d.creditor)} · '
                      '${d.favors.length} kayıt',
                    ),
                    trailing: Text(
                      '${d.count} nöbet',
                      style: theme.textTheme.titleSmall,
                    ),
                    children: [
                      for (final f in d.favors)
                        ListTile(
                          dense: true,
                          leading: Icon(
                            f.helper == d.creditor
                                ? Icons.volunteer_activism_outlined
                                : Icons.replay,
                            size: 20,
                          ),
                          title: Text(FavorLedger.describe(f, name)),
                        ),
                    ],
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
