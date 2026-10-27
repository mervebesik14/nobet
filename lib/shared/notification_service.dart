import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Planlanmış bir bildirim.
typedef ScheduledNotification = ({
  int id,
  DateTime at,
  String title,
  String body,
});

/// Telefon bildirimleri (ay başı hatırlatması). Ses: defibrilatör
/// (`assets/sound/make_sound.py` ile üretilir; Android `res/raw`, iOS
/// uygulama paketi). Testlerde sahte bir sürümle değiştirilir.
class NotificationService {
  NotificationService();

  late final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  static const _sound = 'defibrilator';

  // Android'de kanal sesi sonradan değiştirilemez: ses değişirse kimlik de
  // değişmeli.
  static const _channelId = 'ay_basi_defibrilator';

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      _channelId,
      'Ay başı hatırlatması',
      channelDescription: 'Gelecek ayın listesi oluşturulmadıysa hatırlatır.',
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      sound: RawResourceAndroidNotificationSound(_sound),
    ),
    iOS: DarwinNotificationDetails(
      presentAlert: true,
      presentBanner: true,
      presentList: true,
      presentSound: true,
      sound: '$_sound.wav',
    ),
  );

  Future<void> _init() async {
    if (_ready) return;
    tzdata.initializeTimeZones();
    // Türkiye tek saat dilimi (UTC+3, yaz saati yok).
    tz.setLocalLocation(tz.getLocation('Europe/Istanbul'));
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        // İzin açılışta değil, ilk planlamada istenir.
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
    );
    _ready = true;
  }

  /// Bildirim izni ister (iOS ilk seferde sorar); verildiyse true.
  Future<bool> requestPermission() async {
    await _init();
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return await _plugin
              .resolvePlatformSpecificImplementation<
                IOSFlutterLocalNotificationsPlugin
              >()
              ?.requestPermissions(alert: true, sound: true) ??
          false;
    }
    if (defaultTargetPlatform == TargetPlatform.android) {
      return await _plugin
              .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin
              >()
              ?.requestNotificationsPermission() ??
          false;
    }
    return false;
  }

  /// [ids] kimlikli eski bildirimleri iptal edip [items]'ı planlar.
  Future<void> schedule(
    List<ScheduledNotification> items, {
    required Iterable<int> ids,
  }) async {
    await _init();
    for (final id in ids) {
      await _plugin.cancel(id: id);
    }
    for (final n in items) {
      await _plugin.zonedSchedule(
        id: n.id,
        scheduledDate: tz.TZDateTime(
          tz.local,
          n.at.year,
          n.at.month,
          n.at.day,
          n.at.hour,
          n.at.minute,
        ),
        notificationDetails: _details,
        // Tam saat izni gerektirmez; birkaç dakika kayabilir.
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        title: n.title,
        body: n.body,
      );
    }
  }

  /// Hemen bir bildirim gösterir (sesi denemek için).
  Future<void> show({
    required int id,
    required String title,
    required String body,
  }) async {
    await _init();
    await _plugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: _details,
    );
  }
}

final notificationServiceProvider = Provider<NotificationService>(
  (ref) => NotificationService(),
);
