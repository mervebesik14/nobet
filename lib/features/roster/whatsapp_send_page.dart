import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../logic/day_shift_planner.dart';
import '../../logic/file_names.dart';
import '../../logic/personal_roster.dart';
import '../../logic/phone_number.dart';
import '../../logic/turkish_dates.dart';
import '../../models/models.dart';
import '../../shared/platform_services.dart';
import '../../shared/providers.dart';
import '../../shared/widgets/brand_widgets.dart';
import '../month/month_plan_controller.dart';
import '../people/people_controller.dart';
import 'personal_roster_pdf.dart';

/// Herkese kendi nöbet listesini WhatsApp'tan gönderme. İki yol:
/// - PDF (varsayılan): kişinin PDF'i paylaşım menüsüyle açılır; kullanıcı
///   WhatsApp'ı ve kişiyi seçer (WhatsApp belirli sohbete dosya ekleyerek
///   açılmaya izin vermez).
/// - Mesaj: WhatsApp kişinin sohbetinde, listesi yazılı olarak açılır;
///   numara gerekir, numarası olmayana rehberden eklenir.
class WhatsAppSendPage extends ConsumerStatefulWidget {
  const WhatsAppSendPage({
    super.key,
    required this.personIds,
    required this.dayShifts,
    required this.weekendDays,
    required this.holidayDays,
  });

  /// Listede satırı olan kişiler, sırasıyla.
  final List<String> personIds;
  final Iterable<DayShift> dayShifts;
  final Set<int> weekendDays;
  final Set<int> holidayDays;

  @override
  ConsumerState<WhatsAppSendPage> createState() => _WhatsAppSendPageState();
}

class _WhatsAppSendPageState extends ConsumerState<WhatsAppSendPage> {
  final _sent = <String>{};

  /// PDF olarak mı (paylaşım menüsü), mesaj olarak mı (doğrudan sohbet)?
  bool _asPdf = true;

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

  Future<void> _send(Person person, MonthPlan plan, List<Person> people) =>
      _asPdf ? _sendPdf(person, plan, people) : _sendText(person, plan, people);

  /// Kişinin PDF'ini paylaşım menüsüyle açar.
  Future<void> _sendPdf(
    Person person,
    MonthPlan plan,
    List<Person> people,
  ) async {
    final services = ref.read(platformServicesProvider);
    try {
      final fonts = await services.loadPdfFonts();
      final pdf = await buildPersonalRosterPdf(
        data: PersonalRoster.build(
          plan: plan,
          person: person,
          people: people,
          dayShifts: widget.dayShifts,
          weekendDays: widget.weekendDays,
        ),
        weekendDays: widget.weekendDays,
        holidayDays: widget.holidayDays,
        font: fonts.regular,
        boldFont: fonts.bold,
        createdAt: ref.read(todayProvider),
      );
      await services.sharePdf(
        pdf,
        'nobet-${fileSlug(person.name)}-${plan.year}-'
        '${plan.month.toString().padLeft(2, '0')}.pdf',
      );
      if (mounted) setState(() => _sent.add(person.id));
    } catch (e) {
      if (mounted) _notify('Paylaşılamadı: $e');
    }
  }

  /// WhatsApp'ı kişinin sohbetinde, listesi yazılı olarak açar.
  Future<void> _sendText(
    Person person,
    MonthPlan plan,
    List<Person> people,
  ) async {
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
    final sendable = _asPdf ? rows.length : withPhone.length;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text('${turkishMonthNames[plan.month - 1]} · WhatsApp'),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                  value: true,
                  label: Text('PDF'),
                  icon: Icon(Icons.picture_as_pdf_outlined),
                ),
                ButtonSegment(
                  value: false,
                  label: Text('Mesaj'),
                  icon: Icon(Icons.chat_outlined),
                ),
              ],
              selected: {_asPdf},
              onSelectionChanged: (v) => setState(() {
                _asPdf = v.single;
                _sent.clear();
              }),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: Text(
              _asPdf
                  ? 'Gönder\'e basınca kişinin PDF\'i hazırlanıp paylaşım '
                        'menüsü açılır: WhatsApp\'ı ve kişiyi seç, gönder, '
                        'uygulamaya geri dön. (WhatsApp sohbete dosya '
                        'ekleyerek açılmaya izin vermediği için kişiyi sen '
                        'seçiyorsun.)'
                  : 'Gönder\'e basınca WhatsApp kişinin sohbetinde, kendi '
                        'nöbet listesi yazılı açılır; orada gönderip '
                        'uygulamaya geri dön. Numarası olmayanlara rehberden '
                        'ekleyebilirsin.',
              style: theme.textTheme.bodySmall,
            ),
          ),
          PillHeader(
            'Kişiler',
            trailing: '${_sent.length} / $sendable gönderildi',
          ),
          GroupCard(
            children: [
              for (final p in rows)
                ListTile(
                  key: ValueKey('wa-${p.id}'),
                  title: Text(p.name),
                  subtitle: Text(
                    _asPdf && PhoneNumber.normalize(p.phone) == null
                        ? 'PDF paylaşım menüsüyle'
                        : PhoneNumber.normalize(p.phone) == null
                        ? (p.phone?.isNotEmpty ?? false)
                              ? 'Numara anlaşılamadı: ${p.phone}'
                              : 'Numara yok'
                        : PhoneNumber.display(p.phone!),
                  ),
                  trailing: !_asPdf && PhoneNumber.normalize(p.phone) == null
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
