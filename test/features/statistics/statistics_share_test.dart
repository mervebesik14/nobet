import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:nobet_listesi/data/hive_boxes.dart';
import 'package:nobet_listesi/data/holiday_repository.dart';
import 'package:nobet_listesi/features/statistics/statistics_page.dart';
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
    for (var i = 1; i <= 4; i++) {
      await boxes.people.put(
        'n$i',
        Person(id: 'n$i', name: 'Hemşire $i', role: Role.nurse),
      );
    }
    await boxes.monthPlans.put(
      '2026-09',
      MonthPlan(
        year: 2026,
        month: 9,
        nurseOnly: true,
        assignments: {
          for (var d = 1; d <= 30; d++)
            d: DayAssignment(
              day: d,
              nurseIds: d.isOdd ? const ['n1', 'n2'] : const ['n3', 'n4'],
            ),
        },
      ),
    );
  });

  tearDown(() => Hive.close());

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 3200);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...boxOverrides(boxes),
          todayProvider.overrideWithValue(DateTime(2026, 10, 11)),
          platformServicesProvider.overrideWithValue(services),
        ],
        child: const MaterialApp(home: StatisticsPage()),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> choose(WidgetTester tester, String item) async {
    await tester.tap(find.byTooltip('Paylaş'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(item));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
  }

  testWidgets('PDF olarak paylaşılır', (tester) async {
    await pump(tester);
    await choose(tester, 'PDF olarak paylaş');
    expect(services.calls, ['sharePdf:nobet-istatistik-2026.pdf']);
    expect(String.fromCharCodes(services.lastPdf!.take(5)), '%PDF-');
  });

  testWidgets('kişi karnesi: kişi seçilir, PDF paylaşılır', (tester) async {
    await pump(tester);
    await choose(tester, 'Kişi karnesi (PDF)');
    expect(find.text('Kimin karnesi?'), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byType(SimpleDialog),
        matching: find.text('Hemşire 2'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Karnede hangi sütunlar olsun?'), findsOneWidget);
    // Gün aşırı çift ve 4–5 gün ara çıkarılır.
    await tester.tap(
      find.byKey(const ValueKey('pick-TotalsColumn.everyOtherDay')),
    );
    await tester.tap(find.byKey(const ValueKey('pick-TotalsColumn.longGaps')));
    await tester.tap(find.byKey(const ValueKey('pick-confirm')));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    // Önce önizleme; paylaşılmadan gösterilir.
    expect(find.text('Hemşire 2 · karne'), findsOneWidget);
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('pdf-page-0')), findsOneWidget);
    expect(services.calls, ['pdfPages']);
    await tester.tap(find.widgetWithText(FloatingActionButton, 'Paylaş'));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    expect(services.calls, ['pdfPages', 'sharePdf:karne-hemsire-2-2026.pdf']);
    expect(boxes.meta.get('reportCardColumns'), isNot(contains('longGaps')));
    expect(boxes.meta.get('reportCardColumns'), contains('shifts'));
    expect(String.fromCharCodes(services.lastPdf!.take(5)), '%PDF-');
  });

  testWidgets('Excel olarak paylaşılır', (tester) async {
    await pump(tester);
    await choose(tester, 'Excel olarak paylaş');
    expect(services.calls, ['shareFile:nobet-istatistik-2026.xlsx']);
    final file = services.sharedFiles.single;
    expect(file.mime, XlsxWriter.mimeType);
    expect(String.fromCharCodes(file.bytes.take(2)), 'PK');
  });

  testWidgets('listesi olmayan yılda paylaşılacak bir şey yok', (tester) async {
    await pump(tester);
    await tester.tap(find.byTooltip('Önceki yıl'));
    await tester.pumpAndSettle();
    await choose(tester, 'PDF olarak paylaş');
    expect(services.calls, isEmpty);
    expect(find.text('2025 için paylaşılacak liste yok.'), findsOneWidget);
  });
}
