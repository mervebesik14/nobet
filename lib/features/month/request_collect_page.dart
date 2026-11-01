import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../logic/request_parser.dart';
import '../../logic/turkish_dates.dart';
import '../../models/models.dart';
import '../../shared/platform_services.dart';
import '../../shared/widgets/brand_widgets.dart';
import '../people/people_controller.dart';
import 'month_plan_controller.dart';

/// İstek toplama: kişilere hazır mesajı gönder, gelen cevapları yapıştır,
/// okunanları gözden geçirip seçili aya ekle.
class RequestCollectPage extends ConsumerStatefulWidget {
  const RequestCollectPage({super.key});

  @override
  ConsumerState<RequestCollectPage> createState() => _RequestCollectPageState();
}

class _RequestCollectPageState extends ConsumerState<RequestCollectPage> {
  final _input = TextEditingController();
  RequestParseResult? _result;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _notify(String message) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));

  void _read(MonthPlan plan, List<Person> people) => setState(
    () => _result = RequestParser.parse(
      text: _input.text,
      people: people,
      year: plan.year,
      month: plan.month,
    ),
  );

  Future<void> _paste(MonthPlan plan, List<Person> people) async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text ?? '';
    if (text.trim().isEmpty) {
      _notify('Panoda metin yok.');
      return;
    }
    _input.text = _input.text.trim().isEmpty
        ? text
        : '${_input.text.trimRight()}\n$text';
    _read(plan, people);
  }

  Future<void> _apply() async {
    final result = _result;
    if (result == null || result.requests.isEmpty) return;
    final ok = await ref
        .read(monthPlanProvider.notifier)
        .applyRequests(result.requests);
    if (!mounted) return;
    if (!ok) {
      _notify('Bu ay kilitli; istekler eklenemedi.');
      return;
    }
    _notify('${result.requests.length} kişinin istekleri eklendi.');
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final plan = ref.watch(monthPlanProvider);
    final people = ref
        .watch(peopleProvider)
        .where((p) => p.worksInMonth(plan.year, plan.month))
        .toList();
    final message = RequestParser.message(year: plan.year, month: plan.month);
    final theme = Theme.of(context);
    final result = _result;
    final monthName = turkishMonthNames[plan.month - 1];

    return Scaffold(
      appBar: AppBar(title: Text('$monthName istekleri')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          const PillHeader('1 · Mesajı gönder'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SelectableText(message, style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        onPressed: () => ref
                            .read(platformServicesProvider)
                            .shareText(message),
                        icon: const Icon(Icons.share),
                        label: const Text('Paylaş'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () async {
                          await Clipboard.setData(ClipboardData(text: message));
                          _notify('Mesaj kopyalandı.');
                        },
                        icon: const Icon(Icons.copy),
                        label: const Text('Kopyala'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const PillHeader('2 · Cevapları yapıştır'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'WhatsApp\'ta mesajları seçip kopyalayın (ya da '
                    '"Ad: 3, 5" diye yazın) ve buraya yapıştırın.',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    key: const ValueKey('requests-input'),
                    controller: _input,
                    minLines: 4,
                    maxLines: 12,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: 'Emre Dinç: 3, 7, 12-14 olmaz, izin 20-24',
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.end,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => _paste(plan, people),
                        icon: const Icon(Icons.content_paste),
                        label: const Text('Panodan yapıştır'),
                      ),
                      FilledButton.icon(
                        onPressed: () => _read(plan, people),
                        icon: const Icon(Icons.manage_search),
                        label: const Text('Oku'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (result != null) ..._preview(result, people, theme),
        ],
      ),
    );
  }

  List<Widget> _preview(
    RequestParseResult result,
    List<Person> people,
    ThemeData theme,
  ) {
    String name(String id) => people
        .firstWhere(
          (p) => p.id == id,
          orElse: () => Person(id: id, name: id, role: Role.nurse),
        )
        .name;
    final waiting = [
      for (final p in people)
        if (!result.replied.contains(p.id)) p.name,
    ];
    final noRequest = [
      for (final id in result.replied)
        if (!result.requests.containsKey(id)) name(id),
    ];
    return [
      PillHeader('3 · Okunanlar', trailing: '${result.requests.length} kişi'),
      if (result.requests.isEmpty)
        const Card(
          child: ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('Gün okunamadı.'),
            subtitle: Text(
              'Satırların başında kişinin adı olmalı (ör. "Emre Dinç: 3, 5").',
            ),
          ),
        )
      else
        GroupCard(
          children: [
            for (final MapEntry(key: id, value: r) in result.requests.entries)
              ListTile(
                key: ValueKey('request-$id'),
                title: Text(name(id)),
                subtitle: Text(
                  [
                    if (r.unavailable.isNotEmpty)
                      'İstemiyor: ${RequestParser.compactDays(r.unavailable)}',
                    for (final MapEntry(key: type, value: days)
                        in r.leaves.entries)
                      '${type.label}: ${RequestParser.compactDays(days)}',
                    if (r.overtime) 'Fazla mesai istiyor',
                  ].join('\n'),
                ),
              ),
          ],
        ),
      if (noRequest.isNotEmpty)
        _Note(
          icon: Icons.check_circle_outline,
          text: 'Uygun olmayan günü yok: ${noRequest.join(', ')}',
        ),
      if (waiting.isNotEmpty)
        _Note(
          icon: Icons.hourglass_empty,
          text: 'Henüz yazmayanlar: ${waiting.join(', ')}',
        ),
      for (final w in result.warnings)
        _Note(icon: Icons.warning_amber_rounded, text: w),
      if (result.unmatched.isNotEmpty)
        _Note(
          icon: Icons.help_outline,
          text:
              'Kime ait olduğu anlaşılamadı:\n'
              '${result.unmatched.take(5).join('\n')}'
              '${result.unmatched.length > 5 ? '\n…' : ''}',
          color: theme.colorScheme.error,
        ),
      if (result.requests.isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: FilledButton.icon(
            key: const ValueKey('apply-requests'),
            onPressed: _apply,
            icon: const Icon(Icons.playlist_add_check),
            label: const Text('Ay Planı\'na ekle'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
          ),
        ),
    ];
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.text, this.color});

  final IconData icon;
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = color ?? theme.colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: c),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(color: c),
            ),
          ),
        ],
      ),
    );
  }
}
