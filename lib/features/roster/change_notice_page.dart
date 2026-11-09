import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../../logic/change_notice.dart';
import '../../logic/phone_number.dart';
import '../../logic/turkish_dates.dart';
import '../../models/models.dart';
import '../../shared/platform_services.dart';
import '../../shared/widgets/brand_widgets.dart';
import '../month/month_plan_controller.dart';
import '../people/people_controller.dart';

String _publishedKey(MonthPlan plan) => 'publishedRoster/${plan.key}';

/// [plan] ayının en son paylaşılan (herkese gönderilen) hâli; yoksa null.
Map<int, DayAssignment>? publishedRosterOf(WidgetRef ref, MonthPlan plan) {
  final raw = ref.read(hiveBoxesProvider).meta.get(_publishedKey(plan));
  if (raw is! String) return null;
  try {
    return {
      for (final e in (jsonDecode(raw) as Map).entries)
        int.parse(e.key as String): DayAssignment.fromJson(
          (e.value as Map).cast<String, dynamic>(),
        ),
    };
  } on Object {
    return null;
  }
}

/// Listenin şu anki hâlini "paylaşıldı" olarak saklar; sonraki
/// değişiklikler buna göre bildirilir.
Future<void> markPublished(WidgetRef ref, MonthPlan plan) => ref
    .read(hiveBoxesProvider)
    .meta
    .put(
      _publishedKey(plan),
      jsonEncode({
        for (final e in plan.assignments.entries) '${e.key}': e.value.toJson(),
      }),
    );

/// Paylaşılan listeden bu yana değişen nöbetleri yalnız etkilenen kişilere
/// bildirme.
class ChangeNoticePage extends ConsumerStatefulWidget {
  const ChangeNoticePage({super.key});

  @override
  ConsumerState<ChangeNoticePage> createState() => _ChangeNoticePageState();
}

class _ChangeNoticePageState extends ConsumerState<ChangeNoticePage> {
  final _sent = <String>{};

  Future<void> _send(PersonChange c, MonthPlan plan) async {
    final text = ChangeNotice.message(c, plan.year, plan.month);
    final services = ref.read(platformServicesProvider);
    final number = PhoneNumber.normalize(c.person.phone);
    final opened =
        number != null &&
        (await services.openUrl(PhoneNumber.whatsApp(number, text)) ||
            await services.openUrl(PhoneNumber.whatsAppWeb(number, text)));
    if (!opened) await services.shareText(text);
    if (mounted) setState(() => _sent.add(c.person.id));
  }

  @override
  Widget build(BuildContext context) {
    final plan = ref.watch(monthPlanProvider);
    final theme = Theme.of(context);
    final published = publishedRosterOf(ref, plan);
    final changes = published == null
        ? const <PersonChange>[]
        : ChangeNotice.compute(
            before: published,
            after: plan.assignments,
            people: ref.watch(peopleProvider),
          );

    return Scaffold(
      appBar: AppBar(
        title: Text('${turkishMonthNames[plan.month - 1]} · Değişiklikler'),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Text(
              published == null
                  ? 'Bu ayın listesi henüz paylaşılmamış. Liste PDF, resim, '
                        'Excel ya da WhatsApp ile paylaşılınca o hâli saklanır; '
                        'sonraki değişiklikler buradan yalnız etkilenen '
                        'kişilere bildirilir.'
                  : changes.isEmpty
                  ? 'Paylaşılan listeden bu yana değişiklik yok.'
                  : 'Paylaşılan listeden bu yana ${changes.length} kişinin '
                        'nöbeti değişti. Gönder\'e basınca kişinin WhatsApp '
                        'sohbeti (numarası yoksa paylaşım menüsü) hazır '
                        'mesajla açılır.',
              style: theme.textTheme.bodyMedium,
            ),
          ),
          if (published == null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: OutlinedButton.icon(
                key: const ValueKey('mark-published'),
                onPressed: () async {
                  await markPublished(ref, plan);
                  if (mounted) setState(() {});
                },
                icon: const Icon(Icons.bookmark_added_outlined),
                label: const Text('Şu anki listeyi paylaşılmış say'),
              ),
            ),
          if (changes.isNotEmpty) ...[
            PillHeader(
              'Etkilenenler',
              trailing: '${_sent.length} / ${changes.length} gönderildi',
            ),
            GroupCard(
              children: [
                for (final c in changes)
                  ListTile(
                    key: ValueKey('notice-${c.person.id}'),
                    title: Text(c.person.name),
                    subtitle: Text(
                      ChangeNotice.lines(c, plan.year, plan.month).join('\n'),
                    ),
                    isThreeLine: true,
                    trailing: _sent.contains(c.person.id)
                        ? TextButton.icon(
                            onPressed: () => _send(c, plan),
                            icon: const Icon(Icons.check_circle, size: 18),
                            label: const Text('Gönderildi'),
                          )
                        : FilledButton.icon(
                            onPressed: () => _send(c, plan),
                            icon: const Icon(Icons.send, size: 18),
                            label: const Text('Gönder'),
                          ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: FilledButton.tonalIcon(
                key: const ValueKey('notice-done'),
                onPressed: () async {
                  await markPublished(ref, plan);
                  if (context.mounted) Navigator.of(context).pop();
                },
                icon: const Icon(Icons.done_all),
                label: const Text('Bildirildi: paylaşılan sürümü güncelle'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
