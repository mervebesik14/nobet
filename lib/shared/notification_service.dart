import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Planlanmış bir bildirim.
/// [payload] bildirime dokunulunca ya da düğmesine basılınca geri gelir.
typedef ScheduledNotification = ({
  int id,
  DateTime at,
  String title,
  String body,
  String? payload,
});

/// Telefon bildirimleri (ay başı hatırlatması). Ses: defibrilatör
/// (`assets/sound/make_sound.py` ile üretilir; Android `res/raw`, iOS
/// uygulama paketi). Testlerde sahte bir sürümle değiştirilir.
class NotificationService {
  NotificationService();

  late final _plugin = FlutterLocalNotificationsPlugin();
  Future<void>? _ready;

  static const _sound = 'defibrilator';

  // Android'de kanal sesi sonradan değiştirilemez: ses değişirse kimlik de
  // değişmeli.
  static const _channelId = 'ay_basi_defibrilator';

  /// Bildirimdeki "Başladım" düğmesi.
  static const startedAction = 'started';
  static const _category = 'month_reminder';

  /// Bildirimin düğmesine basılınca: (düğme, payload). Uygulama kapalıyken
  /// basılırsa açılışta bildirilir.
  void Function(String action, String? payload)? onAction;

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      _channelId,
      'Ay başı hatırlatması',
      channelDescription: 'Gelecek ayın listesi oluşturulmadıysa hatırlatır.',
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      sound: RawResourceAndroidNotificationSound(_sound),
      actions: [
        AndroidNotificationAction(
          startedAction,
          'Başladım',
          showsUserInterface: true,
        ),
      ],
    ),
    iOS: DarwinNotificationDetails(
      presentAlert: true,
      presentBanner: true,
      presentList: true,
      presentSound: true,
      sound: '$_sound.wav',
      categoryIdentifier: _category,
    ),
  );

  Future<void> _init() => _ready ??= _initialize();

  Future<void> _initialize() async {
    tzdata.initializeTimeZones();
    // Türkiye tek saat dilimi (UTC+3, yaz saati yok).
    tz.setLocalLocation(tz.getLocation('Europe/Istanbul'));
    await _plugin.initialize(
      settings: InitializationSettings(
        android: const AndroidInitializationSettings('@mipmap/ic_launcher'),
        // İzin açılışta değil, ilk planlamada istenir.
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
          notificationCategories: [
            DarwinNotificationCategory(
              _category,
              actions: [
                DarwinNotificationAction.plain(
                  startedAction,
                  'Başladım',
                  options: {DarwinNotificationActionOption.foreground},
                ),
              ],
            ),
          ],
        ),
      ),
      onDidReceiveNotificationResponse: _respond,
    );
    // Uygulama bildirim düğmesiyle açıldıysa.
    final launch = await _plugin.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp ?? false) {
      if (launch!.notificationResponse case final r?) _respond(r);
    }
  }

  void _respond(NotificationResponse r) {
    if (r.actionId case final action?) onAction?.call(action, r.payload);
  }

  /// Bildirimleri hazırlar (açılışta; düğmeyle açıldıysa [onAction] çağrılır).
  Future<void> init() => _init();

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
        payload: n.payload,
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
