import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../logic/swap_log.dart';
import '../../logic/turkish_dates.dart';
import '../../shared/platform_services.dart';
import '../../shared/widgets/brand_widgets.dart';
import '../month/month_plan_controller.dart';
import '../people/people_controller.dart';

/// Seçili ayın takas defteri: liste oluşturulduktan sonra elle yapılan
/// takaslar ve değişiklikler, ne zaman yapıldığıyla. Metin olarak
/// paylaşılır.
class SwapLogPage extends ConsumerWidget {
  const SwapLogPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plan = ref.watch(monthPlanProvider);
    final entries = SwapLog.build(
      ref.watch(rosterHistoryProvider),
      plan.assignments,
    );
    final names = {for (final p in ref.watch(peopleProvider)) p.id: p.name};
    String name(String id) => names[id] ?? 'Silinmiş kişi';
    final time = DateFormat('d MMMM HH:mm', 'tr_TR');
    final swaps = entries.where((e) => e.isSwap).length;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text('Takas defteri · ${turkishMonthNames[plan.month - 1]}'),
        actions: [
          IconButton(
            tooltip: 'Paylaş',
            icon: const Icon(Icons.share),
            onPressed: () => ref
                .read(platformServicesProvider)
                .shareText(
                  SwapLog.text(
                    year: plan.year,
                    month: plan.month,
                    entries: entries,
                    name: name,
                  ),
                  subject:
                      '${turkishMonthNames[plan.month - 1]} ${plan.year} '
                      'takas defteri',
                ),
          ),
        ],
      ),
      body: entries.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Bu ay liste oluşturulduktan sonra elle değişiklik '
                  'yapılmamış.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                PillHeader(
                  'Değişiklikler',
                  trailing: '$swaps takas · ${entries.length - swaps} diğer',
                ),
                GroupCard(
                  children: [
                    for (final e in entries.reversed)
                      ListTile(
                        leading: Icon(
                          e.isSwap ? Icons.swap_horiz : Icons.edit_outlined,
                          color: e.isSwap ? theme.colorScheme.primary : null,
                        ),
                        title: Text(e.describe(plan.month, name)),
                        subtitle: Text(time.format(e.at)),
                      ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                  child: Text(
                    'Değişiklik geçmişinden çıkarılır: geri alınan '
                    'değişiklikler ve liste oluşturma/sıfırlama burada yer '
                    'almaz.',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
    );
  }
}
