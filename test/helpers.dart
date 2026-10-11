import 'package:flutter_riverpod/misc.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:nobet_listesi/data/hive_boxes.dart';
import 'package:nobet_listesi/data/providers.dart';

/// Diske yazmayan Hive kutuları açar; her test temiz başlar.
Future<HiveBoxes> openTestBoxes() async {
  await Hive.close();
  return HiveBoxes.open(inMemory: true);
}

/// Test kutularını kullanan provider override'ları.
List<Override> boxOverrides(HiveBoxes boxes) => [
  hiveBoxesProvider.overrideWithValue(boxes),
];
