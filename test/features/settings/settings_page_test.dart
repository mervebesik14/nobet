import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:nobet_listesi/app.dart';
import 'package:nobet_listesi/data/backup_service.dart';
import 'package:nobet_listesi/data/hive_boxes.dart';
import 'package:nobet_listesi/features/settings/settings_page.dart';
import 'package:nobet_listesi/models/models.dart';
import 'package:nobet_listesi/shared/platform_services.dart';
import 'package:nobet_listesi/shared/providers.dart';

import '../../helpers.dart';

void main() {
  late HiveBoxes boxes;
  late FakePlatformServices services;

  setUpAll(() => initializeDateFormatting('tr_TR'));

  setUp(() async {
    boxes = await openTestBoxes();
    services = FakePlatformServices();
  });

  tearDown(() => Hive.close());

  Future<void> pump(WidgetTester tester, {Widget? home}) async {
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...boxOverrides(boxes),
          todayProvider.overrideWithValue(DateTime(2026, 10, 11)),
          platformServicesProvider.overrideWithValue(services),
        ],
        child: home ?? const MaterialApp(home: SettingsPage()),
      ),
    );
  }

  RosterSettings saved() => boxes.settings.get('roster')!;

  testWidgets('kurallar değiştirilir ve kaydedilir; varsayılana dönülür', (
    tester,
  ) async {
    await pump(tester);

    await tester.tap(find.text('Art arda gün yasağı'));
    await tester.pumpAndSettle();
    expect(saved().forbidConsecutiveDays, isFalse);

    await tester.tap(find.byTooltip('Gün aşırı zincir: en fazla artır'));
    await tester.pumpAndSettle();
    expect(saved().maxEveryOtherDayChain, 3);
    expect(find.text('Gün aşırı art arda en fazla 3 nöbet.'), findsOneWidget);

    expect(find.text('Ortalamanın üstünde en fazla'), findsNothing);
    await tester.tap(find.text('Fazla nöbet sınırı'));
    await tester.pumpAndSettle();
    expect(saved().maxExtraOverAverage, 2);
    await tester.tap(find.byTooltip('Ortalamanın üstünde en fazla azalt'));
    await tester.pumpAndSettle();
    expect(saved().maxExtraOverAverage, 1);

    await tester.tap(find.text('Resmi tatili hafta sonu say'));
    await tester.pumpAndSettle();
    expect(saved().holidayCountsAsWeekend, isFalse);

    await tester.tap(find.byTooltip('Arife günü çalışma saati azalt'));
    await tester.pumpAndSettle();
    expect(saved().halfDayRequiredHours, 4.5);
    expect(find.text('Arife günü 4,5 saat sayılır.'), findsOneWidget);

    await tester.tap(find.text('Arifeyi yarım gün say'));
    await tester.pumpAndSettle();
    expect(saved().halfDayHolidayIsHalfWorkday, isFalse);
    expect(find.text('Arife günü çalışma saati'), findsNothing);

    await tester.tap(find.text('Varsayılanlara dön'));
    await tester.pumpAndSettle();
    expect(boxes.settings.get('roster'), isNull);
    expect(find.text('3-5 olur, 3-5-7 olmaz.'), findsOneWidget);
  });

  testWidgets('sınırlar: tekniker 0-1, zincir en az 1', (tester) async {
    await pump(tester);
    await tester.tap(find.byTooltip('Günlük radyoloji teknikeri sayısı azalt'));
    await tester.pumpAndSettle();
    expect(saved().techsPerDay, 0);
    final dec = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.remove_circle_outline).at(1),
    );
    expect(dec.onPressed, isNull);
  });

  testWidgets('tema seçimi uygulamaya yansır ve saklanır', (tester) async {
    await pump(tester, home: const NobetApp());
    await tester.tap(find.text('Ayarlar').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Koyu'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.dark,
    );
    expect(boxes.meta.get('themeMode'), 'dark');
  });

  testWidgets('yedeği dışa aktar: tüm veriyi JSON olarak paylaşır', (
    tester,
  ) async {
    await boxes.people.put(
      'a',
      const Person(id: 'a', name: 'Ayşe', role: Role.nurse),
    );
    await pump(tester);
    expect(find.textContaining('Henüz yedek alınmadı.'), findsOneWidget);

    await tester.tap(find.text('Yedeği dışa aktar'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Son yedek: 11 Ekim 2026'), findsOneWidget);

    final file = services.sharedFiles.single;
    expect(file.name, 'nobet-yedek-2026-10-11.json');
    expect(file.mime, 'application/json');
    final backup = BackupService.parse(utf8.decode(file.bytes));
    expect((backup['people'] as List).single['name'], 'Ayşe');
  });

  testWidgets('yedekten geri yükle: onaydan sonra veri değişir', (
    tester,
  ) async {
    // Başka bir "telefondaki" veri.
    await boxes.people.put(
      'x',
      const Person(id: 'x', name: 'Yedekteki Kişi', role: Role.nurse),
    );
    await boxes.settings.put('roster', const RosterSettings(shiftHours: 16));
    final text = BackupService(boxes).exportJson(now: DateTime(2026, 9, 1, 9));
    await boxes.people.clear();
    await boxes.settings.clear();
    await boxes.people.put(
      'a',
      const Person(id: 'a', name: 'Ayşe', role: Role.nurse),
    );
    services.pickedFile = utf8.encode(text);

    await pump(tester, home: const NobetApp());
    expect(find.text('Ayşe'), findsOneWidget); // Kişiler sekmesi

    await tester.tap(find.text('Ayarlar').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Yedekten geri yükle'));
    await tester.pumpAndSettle();
    expect(find.text('Yedekten geri yüklensin mi?'), findsOneWidget);
    expect(find.textContaining('1 Eylül 2026 09:00'), findsOneWidget);
    expect(find.textContaining('Yedekte 1 kişi'), findsOneWidget);

    await tester.tap(find.text('Vazgeç'));
    await tester.pumpAndSettle();
    expect(boxes.people.containsKey('a'), isTrue);

    await tester.tap(find.text('Yedekten geri yükle'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Geri yükle'));
    await tester.pumpAndSettle();

    expect(find.text('Yedek geri yüklendi.'), findsOneWidget);
    expect(boxes.people.keys, ['x']);
    expect(find.text('24 saat'), findsNothing);
    expect(find.text('16 saat'), findsOneWidget); // Ayarlar ekranı güncel

    await tester.tap(find.text('Kişiler').last);
    await tester.pumpAndSettle();
    expect(find.text('Yedekteki Kişi'), findsOneWidget);
    expect(find.text('Ayşe'), findsNothing);
  });

  testWidgets('geçersiz yedek dosyası: veri değişmez, açıklama gösterilir', (
    tester,
  ) async {
    await boxes.people.put(
      'a',
      const Person(id: 'a', name: 'Ayşe', role: Role.nurse),
    );
    services.pickedFile = utf8.encode('{"merhaba": 1}');
    await pump(tester);

    await tester.tap(find.text('Yedekten geri yükle'));
    await tester.pumpAndSettle();
    expect(find.text('Bu dosya bir Nöbetçi yedeği değil.'), findsOneWidget);
    expect(boxes.people.keys, ['a']);
  });

  testWidgets('dosya seçilmezse hiçbir şey olmaz', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Yedekten geri yükle'));
    await tester.pumpAndSettle();
    expect(services.calls, ['pickJsonFile']);
    expect(find.byType(AlertDialog), findsNothing);
  });
}
