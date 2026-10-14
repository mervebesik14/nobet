import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../models/models.dart';
import '../../shared/providers.dart';
import 'people_controller.dart';

/// Silme onayında kullanıcının seçimi.
enum PersonDeleteChoice { delete, deactivate }

/// Kişiyi silmeden önce onay sorar. Kişi kayıtlı listelerde geçiyorsa bunu
/// söyler ve (kişi aktifse) silmek yerine pasif yapma seçeneği de sunar.
/// Vazgeçilirse null döner. İşlemi yapmaz; yalnızca seçimi döndürür.
Future<PersonDeleteChoice?> askPersonDelete(
  BuildContext context,
  WidgetRef ref,
  Person person,
) {
  final referenced = ref.read(peopleProvider.notifier).isReferenced(person.id);
  return showDialog<PersonDeleteChoice>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('${person.name} silinsin mi?'),
      content: Text(
        referenced
            ? '${person.name} kayıtlı ay planlarında geçiyor. Silinirse eski '
                  'listelerdeki nöbetleri "Silinmiş kişi" olarak kalır.'
                  '\n\nAdı eski listelerde kalsın istiyorsanız silmek '
                  'yerine pasif yapabilirsiniz: pasif dönemini (başlangıç '
                  've bitiş) seçersiniz, o dönemdeki nöbetleri başkalarına '
                  'verilir.'
            : '${person.name} kalıcı olarak silinecek.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Vazgeç'),
        ),
        if (referenced)
          TextButton(
            onPressed: () =>
                Navigator.of(context).pop(PersonDeleteChoice.deactivate),
            child: const Text('Pasif yap'),
          ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
            foregroundColor: Theme.of(context).colorScheme.onError,
          ),
          onPressed: () => Navigator.of(context).pop(PersonDeleteChoice.delete),
          child: const Text('Sil'),
        ),
      ],
    ),
  );
}

/// Pasif dönemi: başlangıç ve (boşsa süresiz) bitiş, iki gün dahil.
typedef InactivePeriod = ({DateTime from, DateTime? until});

/// "20 Ekim 2026 – 5 Kasım 2026" ya da "20 Ekim 2026 itibarıyla, süresiz".
String inactivePeriodText(DateTime from, DateTime? until) {
  final date = DateFormat('d MMMM y', 'tr_TR');
  return until == null
      ? '${date.format(from)} itibarıyla, süresiz'
      : '${date.format(from)} – ${date.format(until)}';
}

/// Pasif dönemini (başlangıç–bitiş) sorar. Vazgeçilirse null.
Future<InactivePeriod?> pickInactivePeriod(
  BuildContext context, {
  required DateTime from,
  DateTime? until,
}) => showDialog<InactivePeriod>(
  context: context,
  builder: (context) => _InactivePeriodDialog(from: from, until: until),
);

class _InactivePeriodDialog extends StatefulWidget {
  const _InactivePeriodDialog({required this.from, this.until});

  final DateTime from;
  final DateTime? until;

  @override
  State<_InactivePeriodDialog> createState() => _InactivePeriodDialogState();
}

class _InactivePeriodDialogState extends State<_InactivePeriodDialog> {
  late DateTime _from = widget.from;
  late DateTime? _until = widget.until;

  Future<DateTime?> _pick(DateTime initial, String help, DateTime first) =>
      showDatePicker(
        context: context,
        initialDate: initial.isBefore(first) ? first : initial,
        firstDate: first,
        lastDate: DateTime(2100),
        helpText: help,
        cancelText: 'Vazgeç',
        confirmText: 'Tamam',
      );

  @override
  Widget build(BuildContext context) {
    final date = DateFormat('d MMMM y EEEE', 'tr_TR');
    return AlertDialog(
      title: const Text('Pasif dönemi'),
      contentPadding: const EdgeInsets.fromLTRB(8, 16, 8, 0),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            key: const ValueKey('inactive-from'),
            leading: const Icon(Icons.event_busy_outlined),
            title: const Text('Başlangıç'),
            subtitle: Text(date.format(_from)),
            onTap: () async {
              final picked = await _pick(
                _from,
                'Pasif başlangıcı',
                DateTime(2020),
              );
              if (picked == null) return;
              setState(() {
                _from = picked;
                // Bitiş başlangıçtan önce kalamaz.
                if (_until != null && _until!.isBefore(picked)) {
                  _until = picked;
                }
              });
            },
          ),
          ListTile(
            key: const ValueKey('inactive-until'),
            leading: const Icon(Icons.event_available_outlined),
            title: const Text('Bitiş'),
            subtitle: Text(
              _until == null
                  ? 'Süresiz'
                  : '${date.format(_until!)} (ertesi gün yeniden aktif)',
            ),
            onTap: () async {
              final picked = await _pick(
                _until ?? _from,
                'Pasif bitişi (son pasif gün)',
                _from,
              );
              if (picked != null) setState(() => _until = picked);
            },
            trailing: _until == null
                ? null
                : IconButton(
                    tooltip: 'Süresiz yap',
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() => _until = null),
                  ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Vazgeç'),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.of(context).pop((from: _from, until: _until)),
          child: const Text('Kaydet'),
        ),
      ],
    );
  }
}

/// Pasif yapma sonrası kullanıcıya gösterilen özet.
String deactivationMessage(
  String name,
  DateTime from,
  DateTime? until,
  DeactivationReport report,
) {
  final parts = [
    until == null
        ? '$name ${DateFormat('d MMMM y', 'tr_TR').format(from)} '
              'itibarıyla pasif.'
        : '$name ${inactivePeriodText(from, until)} arası pasif.',
  ];
  if (report.refilled > 0) {
    parts.add('${report.refilled} nöbeti başkasına verildi.');
  }
  if (report.unfilled.isNotEmpty) {
    parts.add(
      '${report.unfilled.length} nöbet için uygun kimse bulunamadı '
      '(${report.unfilled.map(DateFormat('d MMMM', 'tr_TR').format).join(', ')}); '
      'listede "Eksik" olarak görünür.',
    );
  }
  return parts.join(' ');
}

/// Kişinin pasif dönemini sorar, pasif yapar, listeleri onarır ve sonucu
/// bildirir. Pasif yapıldıysa true döner.
Future<bool> deactivateWithDate(
  BuildContext context,
  WidgetRef ref,
  Person person,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final period = await pickInactivePeriod(
    context,
    from: person.inactiveFrom ?? ref.read(todayProvider),
    until: person.inactiveUntil,
  );
  if (period == null) return false;
  final report = await ref
      .read(peopleProvider.notifier)
      .deactivate(person.id, from: period.from, until: period.until);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(
          deactivationMessage(person.name, period.from, period.until, report),
        ),
      ),
    );
  return true;
}
