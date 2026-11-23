import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../../logic/month_open.dart';
import '../../logic/phone_number.dart';
import '../../logic/recurring_requests.dart';
import '../../logic/request_parser.dart';
import '../../logic/turkish_collation.dart';
import '../../logic/turkish_dates.dart';
import '../../models/models.dart';
import '../../shared/platform_services.dart';
import '../../shared/widgets/brand_widgets.dart';
import '../../shared/widgets/motion.dart';
import '../people/people_controller.dart';
import '../roster/roster_flow.dart';
import 'month_open_providers.dart';
import 'month_plan_controller.dart';
import 'recurring_requests_page.dart';
import 'request_collect_page.dart';

/// Ay başı sihirbazı: kalıcı istekler, istek mesajı, cevap takibi,
/// uygunluk kontrolü ve liste oluşturma tek ekranda, sırayla. Yapılan
/// adımlar ay için hatırlanır.
class MonthOpenPage extends ConsumerStatefulWidget {
  const MonthOpenPage({super.key});

  @override
  ConsumerState<MonthOpenPage> createState() => _MonthOpenPageState();
}

class _MonthOpenPageState extends ConsumerState<MonthOpenPage> {
  OpenStep? _running;

  String get _key {
    final plan = ref.read(monthPlanProvider);
    return MonthOpen.key(plan.year, plan.month);
  }

  Set<OpenStep> get _done {
    final raw = ref.read(hiveBoxesProvider).meta.get(_key);
    return raw is List ? MonthOpen.fromNames(raw) : <OpenStep>{};
  }

  Future<void> _mark(OpenStep step) async {
    await ref.read(hiveBoxesProvider).meta.put(_key, [
      for (final s in {..._done, step}) s.name,
    ]);
    if (mounted) setState(() {});
  }

  void _notify(String message) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));

  List<Person> get _people {
    final plan = ref.read(monthPlanProvider);
    return [
      for (final p in ref.read(peopleProvider))
        if (p.worksInMonth(plan.year, plan.month) &&
            (!plan.nurseOnly || p.role == Role.nurse))
          p,
    ]..sort((a, b) => compareTurkish(a.name, b.name));
  }

  Future<void> _run(OpenStep step) async {
    setState(() => _running = step);
    try {
      final ok = switch (step) {
        OpenStep.recurring => await _applyRecurring(),
        OpenStep.collect => await _collect(),
        OpenStep.replies => await _replies(),
        OpenStep.check => await _check(),
        OpenStep.generate => await _generate(),
      };
      if (ok) await _mark(step);
    } finally {
      if (mounted) setState(() => _running = null);
    }
  }

  Future<bool> _applyRecurring() async {
    final plan = ref.read(monthPlanProvider);
    final days = RecurringRequest.forMonth(
      ref.read(recurringRequestsProvider),
      plan.year,
      plan.month,
    );
    if (days.isEmpty) {
      final add = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Kalıcı istek yok'),
          content: const Text(
            'Her ay tekrar eden istekler (ör. "Ayşe her Çarşamba olmaz") '
            'bir kez girilir, her ay buradan işlenir. Şimdi eklemek ister '
            'misin?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Atla'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Ekle'),
            ),
          ],
        ),
      );
      if (add == true && mounted) {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const RecurringRequestsPage(),
          ),
        );
        return false;
      }
      return add == false;
    }
    final ok = await ref.read(monthPlanProvider.notifier).applyRequests({
      for (final e in days.entries) e.key: PersonRequest(unavailable: e.value),
    });
    if (!ok) {
      _notify('Bu ay kilitli; istekler eklenemedi.');
      return false;
    }
    _notify('${days.length} kişinin kalıcı istekleri işlendi.');
    return true;
  }

  Future<bool> _collect() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const RequestCollectPage()));
    return true;
  }

  /// Yazmayanlar listelenir: hatırlatma gönderilir ya da elle "yazdı"
  /// işaretlenir. "Tamam" adımı bitirir.
  Future<bool> _replies() async {
    final plan = ref.read(monthPlanProvider);
    final monthLabel = '${turkishMonthNames[plan.month - 1]} ${plan.year}';
    final text = MonthOpen.reminder(monthLabel);
    final done = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => Consumer(
        builder: (context, ref, _) {
          final replied = ref.watch(requestRepliesProvider);
          final people = _people;
          final waiting = [
            for (final p in people)
              if (!replied.contains(p.id)) p,
          ];
          return SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.8,
              ),
              child: ListView(
                key: const ValueKey('replies-sheet'),
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                children: [
                  Text(
                    '${people.length - waiting.length} / ${people.length} '
                    'kişi yazdı',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Cevaplar "İstek mesajını gönder" adımında okununca '
                    'yazanlar kendiliğinden işaretlenir. Sözlü söyleyeni '
                    'elle işaretleyebilirsin.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  for (final p in people)
                    CheckboxListTile(
                      key: ValueKey('replied-${p.id}'),
                      contentPadding: EdgeInsets.zero,
                      value: replied.contains(p.id),
                      onChanged: (_) => ref
                          .read(requestRepliesProvider.notifier)
                          .toggle(p.id),
                      title: Text(p.name),
                      secondary: replied.contains(p.id)
                          ? null
                          : IconButton(
                              key: ValueKey('remind-${p.id}'),
                              tooltip: 'Hatırlat',
                              icon: const Icon(Icons.notifications_active),
                              onPressed: () => _remind(p, text),
                            ),
                    ),
                  const SizedBox(height: 8),
                  if (waiting.length > 1)
                    OutlinedButton.icon(
                      onPressed: () => ref
                          .read(platformServicesProvider)
                          .shareText(
                            '${waiting.map((p) => p.name).join(', ')}: '
                            '$text',
                          ),
                      icon: const Icon(Icons.share),
                      label: const Text('Yazmayanlara toplu mesaj'),
                    ),
                  const SizedBox(height: 8),
                  FilledButton(
                    key: const ValueKey('replies-done'),
                    onPressed: () => Navigator.of(context).pop(true),
                    child: Text(
                      waiting.isEmpty ? 'Tamam' : 'Bekleyenler olsa da devam',
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    return done ?? false;
  }

  Future<void> _remind(Person p, String text) async {
    final services = ref.read(platformServicesProvider);
    final number = PhoneNumber.normalize(p.phone);
    final opened =
        number != null &&
        (await services.openUrl(PhoneNumber.whatsApp(number, text)) ||
            await services.openUrl(PhoneNumber.whatsAppWeb(number, text)));
    if (!opened) await services.shareText(text);
  }

  Future<bool> _check() async {
    final issues = ref.read(monthFeasibilityProvider).issues;
    if (issues.isEmpty) {
      _notify('Sorun görünmüyor.');
      return true;
    }
    final go = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Bakılacak şeyler var'),
        content: SingleChildScrollView(
          child: Text(issues.map((i) => '• ${i.message}').join('\n')),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Önce düzelteyim'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Yine de devam'),
          ),
        ],
      ),
    );
    return go ?? false;
  }

  Future<bool> _generate() async {
    await generateRoster(context, ref);
    return ref.read(monthPlanProvider).hasRoster;
  }

  @override
  Widget build(BuildContext context) {
    final plan = ref.watch(monthPlanProvider);
    final replied = ref.watch(requestRepliesProvider);
    final recurring = ref.watch(recurringRequestsProvider);
    final feasibility = ref.watch(monthFeasibilityProvider);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final done = _done;
    final next = MonthOpen.next(done);
    final total = OpenStep.values.length;
    final people = _people;
    final names = {for (final p in ref.watch(peopleProvider)) p.id: p.name};
    final recurringLines = RecurringRequest.preview(
      recurring,
      plan.year,
      plan.month,
      (id) => names[id] ?? 'Silinmiş kişi',
    );
    final waiting = [
      for (final p in people)
        if (!replied.contains(p.id)) p.name,
    ];

    String subtitle(OpenStep s) => switch (s) {
      OpenStep.recurring =>
        recurringLines.isEmpty
            ? 'Kalıcı istek yok. "Düzenle" ile eklenir.'
            : recurringLines.join('\n'),
      OpenStep.collect => s.description,
      OpenStep.replies =>
        '${people.length - waiting.length} / ${people.length} kişi yazdı'
            '${waiting.isEmpty ? '' : '\nBekleniyor: ${waiting.join(', ')}'}',
      OpenStep.check =>
        feasibility.issues.isEmpty
            ? 'Sorun görünmüyor.'
            : feasibility.issues.take(3).map((i) => i.message).join('\n'),
      OpenStep.generate =>
        plan.hasRoster ? 'Liste oluşturuldu.' : s.description,
    };

    return Scaffold(
      appBar: AppBar(
        title: Text('${turkishMonthNames[plan.month - 1]} · Ay başı'),
        actions: [
          IconButton(
            tooltip: 'Kalıcı istekler',
            icon: const Icon(Icons.event_repeat),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const RecurringRequestsPage(),
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(top: 12, bottom: 100),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  next == null
                      ? 'Liste hazır. Hepsi tamam.'
                      : '${done.length} / $total adım tamam',
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                    value: done.length / total,
                    minHeight: 8,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          GroupCard(
            children: [
              for (final (i, s) in OpenStep.values.indexed)
                ListTile(
                  key: ValueKey('open-${s.name}'),
                  leading: done.contains(s)
                      ? const SuccessTick(size: 30)
                      : CircleAvatar(
                          radius: 15,
                          backgroundColor: s == next
                              ? scheme.primary
                              : scheme.surfaceContainerHigh,
                          foregroundColor: s == next
                              ? scheme.onPrimary
                              : scheme.onSurfaceVariant,
                          child: Text(
                            '${i + 1}',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                  title: Text(s.label),
                  subtitle: Text(
                    subtitle(s),
                    style: s == OpenStep.check && feasibility.issues.isNotEmpty
                        ? TextStyle(color: scheme.error)
                        : null,
                  ),
                  trailing: TextButton(
                    onPressed: _running == null ? () => _run(s) : null,
                    child: Text(
                      _running == s
                          ? '…'
                          : done.contains(s)
                          ? 'Tekrar'
                          : 'Yap',
                    ),
                  ),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: Text(
              'Adımlar bu ay için hatırlanır; istediğin zaman kaldığın '
              'yerden devam edebilirsin.',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
      floatingActionButton: next == null
          ? null
          : FloatingActionButton.extended(
              key: const ValueKey('open-next'),
              heroTag: null,
              onPressed: _running == null ? () => _run(next) : null,
              icon: const Icon(Icons.play_arrow_rounded),
              label: Text('Sıradaki: ${next.label}'),
            ),
    );
  }
}
