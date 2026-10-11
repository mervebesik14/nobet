import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'features/shell/main_shell.dart';

/// Uygulamanın kökü: tema, Türkçe locale ve ana iskelet.
class NobetApp extends StatelessWidget {
  const NobetApp({super.key});

  static const _seedColor = Colors.teal;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Nöbet Listesi',
      debugShowCheckedModeBanner: false,
      locale: const Locale('tr', 'TR'),
      supportedLocales: const [Locale('tr', 'TR')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: _seedColor),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _seedColor,
          brightness: Brightness.dark,
        ),
      ),
      home: const MainShell(),
    );
  }
}
