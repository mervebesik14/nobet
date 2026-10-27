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

/// Ay başı hatırlatmasının günü (`app_meta`, varsayılan 16): bildirim o gün
/// gelir, Ay ekranındaki kart da o günden itibaren çıkar.
class MonthReminderDay extends Notifier<int> {
  static const _key = 'monthReminderDay';

  @override
  int build() => NextMonthReminder.clampDay(
    ref.watch(hiveBoxesProvider).meta.get(_key) as int? ??
        NextMonthReminder.defaultDay,
  );

  Future<void> set(int day) async {
    state = NextMonthReminder.clampDay(day);
    await ref.read(hiveBoxesProvider).meta.put(_key, state);
  }
}

final monthReminderDayProvider = NotifierProvider<MonthReminderDay, int>(
  MonthReminderDay.new,
);

/// Ay başı bildiriminin saati (`app_meta`, gün içindeki dakika; varsayılan
/// 10:00).
class MonthReminderTime extends Notifier<({int hour, int minute})> {
  static const _key = 'monthReminderMinutes';

  @override
  ({int hour, int minute}) build() {
    final m =
        ref.watch(hiveBoxesProvider).meta.get(_key) as int? ??
        NextMonthReminder.notifyHour * 60;
    return (hour: m ~/ 60 % 24, minute: m % 60);
  }

  Future<void> set(int hour, int minute) async {
    state = (hour: hour, minute: minute);
    await ref.read(hiveBoxesProvider).meta.put(_key, hour * 60 + minute);
  }
}

final monthReminderTimeProvider =
    NotifierProvider<MonthReminderTime, ({int hour, int minute})>(
      MonthReminderTime.new,
    );

/// Hatırlatmanın tekrar aralığı, saat (`app_meta`, varsayılan her gün).
class MonthReminderInterval extends Notifier<int> {
  static const _key = 'monthReminderIntervalHours';

  @override
  int build() {
    final v = ref.watch(hiveBoxesProvider).meta.get(_key);
    return NextMonthReminder.intervals.contains(v)
        ? v as int
        : NextMonthReminder.defaultInterval;
  }

  Future<void> set(int hours) async {
    state = hours;
    await ref.read(hiveBoxesProvider).meta.put(_key, hours);
  }
}

final monthReminderIntervalProvider =
    NotifierProvider<MonthReminderInterval, int>(MonthReminderInterval.new);

/// "Başladım" denen aylar (`app_meta`, "2026-11" gibi): o ayın hatırlatması
/// (bildirim ve kart) durur.
class MonthReminderStarted extends Notifier<Set<String>> {
  static const _key = 'monthReminderStartedMonths';

  static String keyOf(int year, int month) => '$year-$month';

  @override
  Set<String> build() =>
      ((ref.watch(hiveBoxesProvider).meta.get(_key) as List?) ?? const [])
          .cast<String>()
          .toSet();

  bool contains(int year, int month) => state.contains(keyOf(year, month));

  Future<void> markStarted(int year, int month) async {
    final key = keyOf(year, month);
    if (state.contains(key)) return;
    // Son bir yıl yeter.
    final all = [...state, key];
    state = all.skip(all.length > 12 ? all.length - 12 : 0).toSet();
    await ref.read(hiveBoxesProvider).meta.put(_key, state.toList());
  }
}

final monthReminderStartedProvider =
    NotifierProvider<MonthReminderStarted, Set<String>>(
      MonthReminderStarted.new,
    );

/// Bildirim kimlikleri: [firstId] … [firstId] + 47 (iOS en fazla 64 bekleyen
/// bildirim tutar).
const monthReminderFirstId = 1600;
const _maxReminders = 48;

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
  payload: MonthReminderStarted.keyOf(n.month.year, n.month.month),
);

/// Ay başı bildirimlerini kurar: her ayın seçilen günü ve saatinde başlar,
/// ertesi ayın listesi oluşturulana ya da "Başladım" denene kadar seçilen
/// aralıkla tekrarlar. Açılışta ve ay planları değişince (kısa bir
/// beklemeyle) yeniden kurulur; kapatılınca hepsi iptal edilir. Bildirimdeki
/// "Başladım" düğmesi o ayı onaylar. Uygulama kökünde izlenir.
final monthReminderWatcherProvider = Provider<void>((ref) {
  final enabled = ref.watch(monthReminderEnabledProvider);
  final day = ref.watch(monthReminderDayProvider);
  final time = ref.watch(monthReminderTimeProvider);
  final interval = ref.watch(monthReminderIntervalProvider);
  final started = ref.watch(monthReminderStartedProvider);
  final service = ref.watch(notificationServiceProvider);
  final repo = ref.watch(monthPlanRepositoryProvider);
  final boxes = ref.watch(hiveBoxesProvider);
  final ids = [
    for (var i = 0; i < _maxReminders; i++) monthReminderFirstId + i,
  ];
  var askedPermission = false;

  service.onAction = (action, payload) {
    if (action != NotificationService.startedAction) return;
    if (payload?.split('-').map(int.tryParse).toList() case [
      final int y,
      final int m,
    ]) {
      ref.read(monthReminderStartedProvider.notifier).markStarted(y, m);
    }
  };

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
        acknowledged: (y, m) =>
            started.contains(MonthReminderStarted.keyOf(y, m)),
        count: _maxReminders,
        day: day,
        hour: time.hour,
        minute: time.minute,
        intervalHours: interval,
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
