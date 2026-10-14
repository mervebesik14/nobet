import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import 'app.dart';
import 'data/hive_boxes.dart';
import 'data/holiday_repository.dart';
import 'data/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Tarih biçimleri (ay ve gün adları) Türkçe.
  await initializeDateFormatting('tr_TR');
  Intl.defaultLocale = 'tr_TR';

  // Tüm veri cihazda Hive ile saklanır.
  await Hive.initFlutter();
  final boxes = await HiveBoxes.open();

  // Bu yılın ve gelecek yılın Türkiye tatilleri ilk açılışta yüklenir.
  final holidays = HolidayRepository(boxes.holidays, boxes.meta);
  await holidays.tagReligiousHolidays();
  final thisYear = DateTime.now().year;
  await holidays.ensureYearSeeded(thisYear);
  await holidays.ensureYearSeeded(thisYear + 1);

  runApp(
    ProviderScope(
      overrides: [hiveBoxesProvider.overrideWithValue(boxes)],
      child: const NobetApp(),
    ),
  );
}
