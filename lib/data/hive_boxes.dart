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
  });

  static const peopleBox = 'people';
  static const holidaysBox = 'holidays';
  static const monthPlansBox = 'month_plans';
  static const settingsBox = 'settings';

  final Box<Person> people;
  final Box<Holiday> holidays;
  final Box<MonthPlan> monthPlans;
  final Box<RosterSettings> settings;

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
    );
  }

  Future<void> close() async {
    await people.close();
    await holidays.close();
    await monthPlans.close();
    await settings.close();
  }
}
