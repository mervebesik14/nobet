import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Tarih biçimleri (ay ve gün adları) Türkçe.
  await initializeDateFormatting('tr_TR');
  Intl.defaultLocale = 'tr_TR';

  // Tüm veri cihazda Hive ile saklanır; kutular Level 1'de açılacak.
  await Hive.initFlutter();

  runApp(const ProviderScope(child: NobetApp()));
}
