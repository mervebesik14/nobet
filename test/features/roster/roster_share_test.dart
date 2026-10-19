import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:nobet_listesi/data/hive_boxes.dart';
import 'package:nobet_listesi/data/holiday_repository.dart';
import 'package:nobet_listesi/features/roster/roster_page.dart';
import 'package:nobet_listesi/logic/xlsx_writer.dart';
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
    await HolidayRepository(boxes.holidays, boxes.meta).ensureYearSeeded(2026);
    await boxes.people.putAll({
      'a': const Person(id: 'a', name: 'Ayşe', role: Role.nurse),
      'b': const Person(id: 'b', name: 'Banu', role: Role.nurse),
      't': const Person(id: 't', name: 'Ali', role: Role.radiologyTech),
    });
    await boxes.monthPlans.put(
      '2026-10',
      const MonthPlan(
        year: 2026,
        month: 10,
        assignments: {
          1: DayAssignment(day: 1, nurseIds: ['a', 'b'], techId: 't'),
        },
      ),
    );
  });

  tearDown(() => Hive.close());

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(2400, 3200);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...boxOverrides(boxes),
          todayProvider.overrideWithValue(DateTime(2026, 10, 11)),
          platformServicesProvider.overrideWithValue(services),
        ],
        child: const MaterialApp(home: RosterPage()),
      ),
    );
  }

  /// Paylaş menüsünden [item]; tüm liste için açılan pencerede [details]
  /// true → "Liste ve ayrıntılar", false → "Yalnız liste".
  Future<void> choose(WidgetTester tester, String item, {bool? details}) async {
    await tester.tap(find.byTooltip('Paylaş'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(item));
    await tester.pumpAndSettle();
    if (details != null) {
      await tester.tap(
        find.byKey(
          ValueKey(details ? 'share-with-details' : 'share-list-only'),
        ),
      );
    }
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
  }

  /// Excel dosyasındaki sayfa adları.
  List<String> sheetNames(List<int> xlsx) {
    final workbook = ZipDecoder()
        .decodeBytes(xlsx)
        .firstWhere((f) => f.name == 'xl/workbook.xml');
    return RegExp(
      r'<sheet name="([^"]+)"',
    ).allMatches(utf8.decode(workbook.content)).map((m) => m[1]!).toList();
  }

  bool isPdf(List<int>? bytes) =>
      bytes != null && String.fromCharCodes(bytes.take(5)) == '%PDF-';

  testWidgets('PDF olarak paylaş', (tester) async {
    await pump(tester);
    await choose(tester, 'PDF olarak paylaş', details: true);
    expect(services.calls, ['sharePdf:nobet-listesi-2026-10.pdf']);
    expect(isPdf(services.lastPdf), isTrue);
  });

  testWidgets('tüm liste: önce ne paylaşılacağı sorulur', (tester) async {
    await pump(tester);
    await choose(tester, 'PDF olarak paylaş');
    expect(find.text('Ne paylaşılsın?'), findsOneWidget);
    expect(find.text('Yalnız liste'), findsOneWidget);
    expect(find.text('Liste ve ayrıntılar'), findsOneWidget);
    // Vazgeçilirse hiçbir şey paylaşılmaz.
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.text('Ne paylaşılsın?'), findsNothing);
    expect(services.calls, isEmpty);
  });

  testWidgets('yalnız liste PDF\'i ayrıntılısından küçüktür', (tester) async {
    await pump(tester);
    await choose(tester, 'PDF olarak paylaş', details: false);
    final listOnly = services.lastPdf!;
    await choose(tester, 'PDF olarak paylaş', details: true);
    final withDetails = services.lastPdf!;
    expect(services.calls, [
      'sharePdf:nobet-listesi-2026-10.pdf',
      'sharePdf:nobet-listesi-2026-10.pdf',
    ]);
    expect(isPdf(listOnly), isTrue);
    expect(listOnly.length, lessThan(withDetails.length));
  });

  testWidgets('Görsel (PNG) olarak paylaş', (tester) async {
    await pump(tester);
    await choose(tester, 'Görsel (PNG) olarak paylaş', details: false);
    expect(services.calls, ['pdfToPng', 'shareFile:nobet-listesi-2026-10.png']);
    expect(services.sharedFiles.single.mime, 'image/png');
    expect(isPdf(services.lastPdf), isTrue);
  });

  testWidgets('Excel olarak paylaş', (tester) async {
    await pump(tester);
    await choose(tester, 'Excel olarak paylaş', details: true);
    expect(services.calls, ['shareFile:nobet-listesi-2026-10.xlsx']);
    final file = services.sharedFiles.single;
    expect(file.mime, XlsxWriter.mimeType);
    // xlsx bir zip dosyasıdır: "PK" ile başlar.
    expect(String.fromCharCodes(file.bytes.take(2)), 'PK');
    expect(sheetNames(file.bytes), ['Nöbet Listesi', 'Mesai Özeti']);
  });

  testWidgets('Excel yalnız liste: tek sayfa', (tester) async {
    await pump(tester);
    await choose(tester, 'Excel olarak paylaş', details: false);
    expect(sheetNames(services.sharedFiles.single.bytes), ['Nöbet Listesi']);
  });

  testWidgets('Yazdır', (tester) async {
    await pump(tester);
    await choose(tester, 'Yazdır');
    expect(find.text('Ne yazdırılsın?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('share-with-details')));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    expect(services.calls, ['printPdf:Ekim 2026 Nöbet Listesi']);
  });

  testWidgets('kişiye özel liste mesaj olarak paylaşılır', (tester) async {
    await pump(tester);
    await choose(tester, 'Kişiye özel liste (mesaj)');
    expect(find.text('Kimin listesi?'), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byType(SimpleDialog),
        matching: find.text('Banu'),
      ),
    );
    await tester.pumpAndSettle();

    expect(services.calls, ['shareText']);
    final text = services.sharedTexts.single;
    expect(text, startsWith('Banu · Ekim 2026 nöbetleri'));
    expect(text, contains('• 1 Ekim Perşembe — 24'));
    expect(text, contains('Hemşire: Ayşe, Banu'));
    expect(text, contains('Radyoloji: Ali'));
    expect(text, endsWith('Toplam: 1 nöbet'));
  });

  testWidgets('kişiye özel liste PDF olarak paylaşılır', (tester) async {
    await pump(tester);
    await choose(tester, 'Kişiye özel liste (PDF)');
    expect(find.text('Kimin listesi?'), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byType(SimpleDialog),
        matching: find.text('Banu'),
      ),
    );
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();

    expect(services.calls, ['sharePdf:nobet-banu-2026-10.pdf']);
    expect(isPdf(services.lastPdf), isTrue);
  });

  testWidgets('herkesin kişiye özel PDF\'i tek seferde paylaşılır', (
    tester,
  ) async {
    await pump(tester);
    await choose(tester, 'Herkesin listesi (PDF)');
    expect(services.calls, ['shareFiles:3']);
    expect(services.sharedFiles.map((f) => f.name), {
      'nobet-ayse-2026-10.pdf',
      'nobet-banu-2026-10.pdf',
      'nobet-ali-2026-10.pdf',
    });
    for (final f in services.sharedFiles) {
      expect(f.mime, 'application/pdf');
      expect(isPdf(f.bytes), isTrue);
    }
  });

  testWidgets('isme dokununca kişi vurgulanır ve özeti çıkar', (tester) async {
    await pump(tester);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('highlight-summary')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('name-b')));
    await tester.pumpAndSettle();
    final summary = find.byKey(const ValueKey('highlight-summary'));
    expect(summary, findsOneWidget);
    expect(
      find.descendant(
        of: summary,
        matching: find.textContaining('1 nöbet · 0 hafta sonu · 0 gün aşırı'),
      ),
      findsOneWidget,
    );

    // Aynı isme yeniden dokununca vurgu kalkar.
    await tester.tap(find.byKey(const ValueKey('name-b')));
    await tester.pumpAndSettle();
    expect(summary, findsNothing);

    // Kapat düğmesiyle de kaldırılır.
    await tester.tap(find.byKey(const ValueKey('name-a')));
    await tester.pumpAndSettle();
    expect(summary, findsOneWidget);
    await tester.tap(find.byTooltip('Vurguyu kaldır'));
    await tester.pumpAndSettle();
    expect(summary, findsNothing);
  });
}
