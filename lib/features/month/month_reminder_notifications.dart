import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../../logic/next_month_reminder.dart';
import '../../logic/turkish_dates.dart';
import '../../shared/notification_service.dart';
import '../../shared/providers.dart';

/// Ay başı bildirimi açık mı? (`app_meta`, varsayılan açık)
class MonthReminderEnabled extends Notifier<bool> {
  static const _key = 'monthReminderNotifications';

  @override
  bool build() => ref.watch(hiveBoxesProvider).meta.get(_key) as bool? ?? true;

  Future<void> set(bool value) async {
    state = value;
    await ref.read(hiveBoxesProvider).meta.put(_key, value);
  }
}

final monthReminderEnabledProvider =
    NotifierProvider<MonthReminderEnabled, bool>(MonthReminderEnabled.new);

/// Bildirim kimlikleri: [firstId] … [firstId] + 11.
const monthReminderFirstId = 1600;
const _maxReminders = 12;

/// Bildirim metni: "Aralık listesi henüz oluşturulmadı…".
ScheduledNotification monthReminderNotification(
  int index,
  ({DateTime at, DateTime month}) n,
) => (
  id: monthReminderFirstId + index,
  at: n.at,
  title: 'Nöbetçi',
  body:
      '${turkishMonthNames[n.month.month - 1]} listesi henüz oluşturulmadı. '
      'İstenmeyen günleri ve izinleri toplamaya başla.',
);

/// Ay başı bildirimlerini kurar: her ayın 16'sı 10:00, ertesi ayın listesi
/// yoksa (ileriye 3 ay). Açılışta ve ay planları değişince (kısa bir
/// beklemeyle) yeniden kurulur; kapatılınca hepsi iptal edilir. Uygulama
/// kökünde izlenir.
final monthReminderWatcherProvider = Provider<void>((ref) {
  final enabled = ref.watch(monthReminderEnabledProvider);
  final service = ref.watch(notificationServiceProvider);
  final repo = ref.watch(monthPlanRepositoryProvider);
  final boxes = ref.watch(hiveBoxesProvider);
  final ids = [
    for (var i = 0; i < _maxReminders; i++) monthReminderFirstId + i,
  ];
  var askedPermission = false;

  Future<void> sync() async {
    try {
      if (!enabled) {
        await service.schedule(const [], ids: ids);
        return;
      }
      if (!askedPermission) {
        askedPermission = true;
        await service.requestPermission();
      }
      final upcoming = NextMonthReminder.notifications(
        now: ref.read(clockProvider)(),
        hasRoster: (y, m) => repo.get(y, m)?.hasRoster ?? false,
      );
      await service.schedule([
        for (var i = 0; i < upcoming.length; i++)
          monthReminderNotification(i, upcoming[i]),
      ], ids: ids);
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
