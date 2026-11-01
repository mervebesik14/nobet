import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../logic/day_shift_planner.dart';
import '../../logic/personal_roster.dart';
import '../../logic/phone_number.dart';
import '../../logic/turkish_dates.dart';
import '../../models/models.dart';
import '../../shared/platform_services.dart';
import '../../shared/widgets/brand_widgets.dart';
import '../month/month_plan_controller.dart';
import '../people/people_controller.dart';

/// Herkese kendi nöbet listesini WhatsApp'tan gönderme: her kişi için
/// WhatsApp, numarası ve hazır mesajıyla açılır; kullanıcı gönder'e basıp
/// geri döner. Numarası olmayana rehberden numara eklenir.
class WhatsAppSendPage extends ConsumerStatefulWidget {
  const WhatsAppSendPage({
    super.key,
    required this.personIds,
    required this.dayShifts,
  });

  /// Listede satırı olan kişiler, sırasıyla.
  final List<String> personIds;
  final Iterable<DayShift> dayShifts;

  @override
  ConsumerState<WhatsAppSendPage> createState() => _WhatsAppSendPageState();
}

class _WhatsAppSendPageState extends ConsumerState<WhatsAppSendPage> {
  final _sent = <String>{};

  void _notify(String message) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));

  Future<void> _addPhone(Person person) async {
    final picked = await ref.read(platformServicesProvider).pickContactPhone();
    if (picked == null || !mounted) return;
    if (PhoneNumber.normalize(picked.phone) == null) {
      _notify('"${picked.phone}" numarası anlaşılamadı.');
      return;
    }
    await ref
        .read(peopleProvider.notifier)
        .setPhone(person.id, PhoneNumber.display(picked.phone));
  }

  Future<void> _send(Person person, MonthPlan plan, List<Person> people) async {
    final number = PhoneNumber.normalize(person.phone);
    if (number == null) return;
    final text = PersonalRoster.text(
      plan: plan,
      person: person,
      people: people,
      dayShifts: widget.dayShifts,
    );
    final services = ref.read(platformServicesProvider);
    // WhatsApp yüklü değilse tarayıcıda wa.me.
    final opened =
        await services.openUrl(PhoneNumber.whatsApp(number, text)) ||
        await services.openUrl(PhoneNumber.whatsAppWeb(number, text));
    if (!mounted) return;
    if (opened) {
      setState(() => _sent.add(person.id));
    } else {
      _notify('WhatsApp açılamadı.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final plan = ref.watch(monthPlanProvider);
    final people = ref.watch(peopleProvider);
    final byId = {for (final p in people) p.id: p};
    final rows = [for (final id in widget.personIds) ?byId[id]];
    final withPhone = rows.where((p) => PhoneNumber.normalize(p.phone) != null);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text('${turkishMonthNames[plan.month - 1]} · WhatsApp'),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Text(
              'Gönder\'e basınca WhatsApp kişinin kendi nöbet listesiyle '
              'açılır; orada gönderip uygulamaya geri dön. Numarası '
              'olmayanlara rehberden ekleyebilirsin.',
              style: theme.textTheme.bodySmall,
            ),
          ),
          PillHeader(
            'Kişiler',
            trailing: '${_sent.length} / ${withPhone.length} gönderildi',
          ),
          GroupCard(
            children: [
              for (final p in rows)
                ListTile(
                  key: ValueKey('wa-${p.id}'),
                  title: Text(p.name),
                  subtitle: Text(
                    PhoneNumber.normalize(p.phone) == null
                        ? (p.phone?.isNotEmpty ?? false)
                              ? 'Numara anlaşılamadı: ${p.phone}'
                              : 'Numara yok'
                        : PhoneNumber.display(p.phone!),
                  ),
                  trailing: PhoneNumber.normalize(p.phone) == null
                      ? OutlinedButton.icon(
                          onPressed: () => _addPhone(p),
                          icon: const Icon(Icons.contacts_outlined, size: 18),
                          label: const Text('Rehberden'),
                        )
                      : _sent.contains(p.id)
                      ? TextButton.icon(
                          onPressed: () => _send(p, plan, people),
                          icon: const Icon(Icons.check_circle, size: 18),
                          label: const Text('Gönderildi'),
                        )
                      : FilledButton.icon(
                          onPressed: () => _send(p, plan, people),
                          icon: const Icon(Icons.send, size: 18),
                          label: const Text('Gönder'),
                        ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
