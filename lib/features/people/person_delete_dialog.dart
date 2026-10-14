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
                  '${person.isActive ? '\n\nAdı eski listelerde kalsın '
                            'istiyorsanız silmek yerine pasif yapabilirsiniz: '
                            'hangi günden itibaren pasif olacağını seçersiniz, '
                            'o günden sonraki nöbetleri başkalarına verilir.' : ''}'
            : '${person.name} kalıcı olarak silinecek.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Vazgeç'),
        ),
        if (referenced && person.isActive)
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

/// Pasif başlangıç tarihini sorar. Vazgeçilirse null.
Future<DateTime?> pickInactiveFrom(BuildContext context, DateTime initial) =>
    showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      helpText: 'Hangi günden itibaren pasif?',
      cancelText: 'Vazgeç',
      confirmText: 'Tamam',
    );

/// Pasif yapma sonrası kullanıcıya gösterilen özet.
String deactivationMessage(
  String name,
  DateTime from,
  DeactivationReport report,
) {
  final date = DateFormat('d MMMM y', 'tr_TR');
  final parts = ['$name ${date.format(from)} itibarıyla pasif.'];
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

/// Kişiyi tarih sorarak pasif yapar, listeleri onarır ve sonucu bildirir.
/// Pasif yapıldıysa true döner.
Future<bool> deactivateWithDate(
  BuildContext context,
  WidgetRef ref,
  Person person,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final from = await pickInactiveFrom(
    context,
    person.inactiveFrom ?? ref.read(todayProvider),
  );
  if (from == null) return false;
  final report = await ref
      .read(peopleProvider.notifier)
      .deactivate(person.id, from: from);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(content: Text(deactivationMessage(person.name, from, report))),
    );
  return true;
}
