import 'dart:typed_data';

import 'package:hive_ce/hive_ce.dart';

import 'hive_registrar.g.dart';
import '../models/models.dart';

/// Uygulamanın Hive kutuları. [open] çağrılmadan önce Hive başlatılmış olmalı
/// (uygulamada `Hive.initFlutter()`, testlerde `Hive.init(geçiciKlasör)`).
class HiveBoxes {
  HiveBoxes._({
    required this.people,
    required this.holidays,
    required this.monthPlans,
    required this.settings,
    required this.meta,
    required this.history,
    required this.autoBackups,
  });

  static const peopleBox = 'people';
  static const holidaysBox = 'holidays';
  static const monthPlansBox = 'month_plans';
  static const settingsBox = 'settings';
  static const metaBox = 'app_meta';
  static const historyBox = 'roster_history';
  static const autoBackupsBox = 'auto_backups';

  final Box<Person> people;
  final Box<Holiday> holidays;
  final Box<MonthPlan> monthPlans;
  final Box<RosterSettings> settings;

  /// Uygulamanın kendi kayıtları (ör. hazır tatillerin yüklendiği yıllar).
  final Box<dynamic> meta;

  /// Ay anahtarı (`yyyy-MM`) → liste değişiklik geçmişi (JSON metinleri).
  /// Cihaza özeldir, yedeğe girmez.
  final Box<dynamic> history;

  /// Otomatik yedekler: zaman (ISO 8601) → yedek JSON metni. Cihaza özeldir,
  /// yedeğe girmez ve geri yüklemede silinmez.
  final Box<dynamic> autoBackups;

  static bool _adaptersRegistered = false;

  /// [inMemory] true ise kutular diske yazılmaz (widget testleri için).
  static Future<HiveBoxes> open({bool inMemory = false}) async {
    if (!_adaptersRegistered) {
      Hive.registerAdapters();
      _adaptersRegistered = true;
    }
    Uint8List? bytes() => inMemory ? Uint8List(0) : null;
    return HiveBoxes._(
      people: await Hive.openBox<Person>(peopleBox, bytes: bytes()),
      holidays: await Hive.openBox<Holiday>(holidaysBox, bytes: bytes()),
      monthPlans: await Hive.openBox<MonthPlan>(monthPlansBox, bytes: bytes()),
      settings: await Hive.openBox<RosterSettings>(settingsBox, bytes: bytes()),
      meta: await Hive.openBox<dynamic>(metaBox, bytes: bytes()),
      history: await Hive.openBox<dynamic>(historyBox, bytes: bytes()),
      autoBackups: await Hive.openBox<dynamic>(autoBackupsBox, bytes: bytes()),
    );
  }

  Future<void> close() async {
    await people.close();
    await holidays.close();
    await monthPlans.close();
    await settings.close();
    await meta.close();
    await history.close();
    await autoBackups.close();
  }
}
