import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/models.dart';
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
                            'yeni listelere alınmaz.' : ''}'
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
