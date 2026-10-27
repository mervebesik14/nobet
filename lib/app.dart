import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/auto_backup_service.dart';
import 'data/providers.dart';
import 'features/month/month_reminder_notifications.dart';

import 'features/shell/main_shell.dart';
import 'shared/brand.dart';

/// Uygulamanın kökü: tema, Türkçe locale ve ana iskelet.
class NobetApp extends ConsumerWidget {
  const NobetApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Veri değiştikçe telefona sessizce yedek alınır.
    ref.watch(autoBackupWatcherProvider);
    // Gelecek ayın listesi yoksa ayın seçilen günü telefon bildirimi.
    ref.watch(monthReminderWatcherProvider);
    return MaterialApp(
      themeMode: ref.watch(themeModeProvider),
      title: 'Nöbetçi',
      debugShowCheckedModeBanner: false,
      locale: const Locale('tr', 'TR'),
      supportedLocales: const [Locale('tr', 'TR')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: brandTheme(Brightness.light),
      darkTheme: brandTheme(Brightness.dark),
      home: const MainShell(),
    );
  }
}
