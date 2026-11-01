import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../../logic/shift_reminder.dart';
import '../../shared/notification_service.dart';
import '../../shared/providers.dart';
import '../people/people_controller.dart';

/// Telefonu kullanan kişi ("Ben"): nöbet hatırlatması onun nöbetleri için
/// kurulur (`app_meta`, yoksa kapalı).
class SelfPerson extends Notifier<String?> {
  static const _key = 'selfPersonId';

  @override
  String? build() => ref.watch(hiveBoxesProvider).meta.get(_key) as String?;

  Future<void> set(String? personId) async {
    state = personId;
    final meta = ref.read(hiveBoxesProvider).meta;
    if (personId == null) {
      await meta.delete(_key);
    } else {
      await meta.put(_key, personId);
    }
  }
}

final selfPersonProvider = NotifierProvider<SelfPerson, String?>(
  SelfPerson.new,
);

/// Kendi nöbet hatırlatmasının saati (`app_meta`, gün içindeki dakika;
/// varsayılan 20:00, nöbetten önceki akşam).
class ShiftReminderTime extends Notifier<({int hour, int minute})> {
  static const _key = 'shiftReminderMinutes';

  @override
  ({int hour, int minute}) build() {
    final m =
        ref.watch(hiveBoxesProvider).meta.get(_key) as int? ??
        ShiftReminder.defaultHour * 60;
    return (hour: m ~/ 60 % 24, minute: m % 60);
  }

  Future<void> set(int hour, int minute) async {
    state = (hour: hour, minute: minute);
    await ref.read(hiveBoxesProvider).meta.put(_key, hour * 60 + minute);
  }
}

final shiftReminderTimeProvider =
    NotifierProvider<ShiftReminderTime, ({int hour, int minute})>(
      ShiftReminderTime.new,
    );

/// Bildirim kimlikleri: [shiftReminderFirstId] … +29.
const shiftReminderFirstId = 1700;
const _maxReminders = 30;

/// Seçilen kişinin nöbet hatırlatmalarını kurar: liste değişince (kısa
/// beklemeyle) yeniden; kişi seçilmemişse hepsi iptal. Uygulama kökünde
/// izlenir.
final shiftReminderWatcherProvider = Provider<void>((ref) {
  final personId = ref.watch(selfPersonProvider);
  final time = ref.watch(shiftReminderTimeProvider);
  final service = ref.watch(notificationServiceProvider);
  final repo = ref.watch(monthPlanRepositoryProvider);
  final boxes = ref.watch(hiveBoxesProvider);
  final ids = [
    for (var i = 0; i < _maxReminders; i++) shiftReminderFirstId + i,
  ];

  Future<void> sync() async {
    try {
      if (personId == null) {
        await service.schedule(const [], ids: ids, startedButton: false);
        return;
      }
      await service.requestPermission();
      final people = {for (final p in ref.read(peopleProvider)) p.id: p.name};
      final items = ShiftReminder.upcoming(
        now: ref.read(clockProvider)(),
        plans: repo.getAll(),
        personId: personId,
        hour: time.hour,
        minute: time.minute,
        count: _maxReminders,
      );
      await service.schedule(
        [
          for (var i = 0; i < items.length; i++)
            (
              id: shiftReminderFirstId + i,
              at: items[i].at,
              title: 'Yarın nöbetin var',
              body: ShiftReminder.body(items[i], (id) => people[id] ?? '?'),
              payload: null,
            ),
        ],
        ids: ids,
        startedButton: false,
      );
    } on Object {
      // Bildirim kurulamazsa (izin yok, platform desteklemiyor) sessiz geç.
    }
  }

  Timer? timer;
  void later() {
    timer?.cancel();
    timer = Timer(const Duration(seconds: 2), sync);
  }

  final sub = boxes.monthPlans.watch().listen((_) => later());
  later();
  ref.onDispose(() {
    timer?.cancel();
    sub.cancel();
  });
});
