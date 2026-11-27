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

  testWidgets('izinler bölümü: sayılar ve ay ay günler', (tester) async {
    await boxes.monthPlans.put(
      '2026-09',
      boxes.monthPlans
          .get('2026-09')!
          .copyWith(
            // 7–11 Eylül Pzt–Cuma: 5 iş günü; 12–13 hafta sonu sayılmaz.
            annualLeave: {
              'n1': [7, 8, 9, 10, 11, 12, 13],
            },
            sickLeave: {
              'n2': [21, 22],
            },
          ),
    );
    // Listesi olmayan ayın izni de sayılır.
    await boxes.monthPlans.put(
      '2026-12',
      const MonthPlan(
        year: 2026,
        month: 12,
        radiationLeave: {
          'n1': [1, 2, 3],
        },
      ),
    );
    await pump(tester);
    final tile = find.byKey(const ValueKey('leave-n1'));
    await tester.scrollUntilVisible(
      tile,
      300,
      scrollable: find
          .byWidgetPredicate(
            (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
          )
          .first,
    );
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: tile,
        matching: find.text('Yıllık izin 5 iş günü · Şua izni 3 gün'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('leave-n2')),
        matching: find.text('Rapor 2 gün'),
      ),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('leave-n3')), findsNothing);
    await tester.tap(tile);
    await tester.pumpAndSettle();
    final detail = find.byKey(const ValueKey('leave-detail'));
    expect(
      find.descendant(of: detail, matching: find.textContaining('Eylül: 7')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: detail, matching: find.textContaining('Aralık: 1')),
      findsOneWidget,
    );
  });

  testWidgets('yıl sonu tahmini bölümü görünür', (tester) async {
    await pump(tester);
    final tile = find.byKey(const ValueKey('projection-n1'));
    await tester.scrollUntilVisible(
      tile,
      300,
      scrollable: find
          .byWidgetPredicate(
            (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
          )
          .first,
    );
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: tile,
        matching: find.textContaining('Şimdi 15 nöbet, payından 0'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('yıl kapanışı: karneler, izin, bayram planı', (tester) async {
    await pump(tester);
    await choose(tester, 'Yılı kapat');
    expect(find.text('2026 · Yıl kapanışı'), findsOneWidget);
    expect(find.text('0 / 5 adım tamam'), findsOneWidget);

    Future<void> doStep(String name) async {
      await tester.tap(
        find.descendant(
          of: find.byKey(ValueKey('year-$name')),
          matching: find.text('Yap'),
        ),
      );
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
    }

    await doStep('reports');
    expect(services.calls, contains('shareFiles:4'));
    expect(services.sharedFiles.first.name, 'karne-hemsire-1-2026.pdf');

    await doStep('leave');
    expect(find.text('İzin hakkı girilmiş kişi yok.'), findsWidgets);
    await tester.tap(find.text('Tamam'));
    await tester.pumpAndSettle();

    await doStep('holidays');
    expect(find.textContaining('2027 bayram ve tatil planı'), findsOneWidget);
    await tester.tap(find.text('Paylaş').last);
    await tester.pumpAndSettle();
    expect(services.sharedTexts.last, contains('Kurban Bayramı'));
    expect(find.text('3 / 5 adım tamam'), findsOneWidget);
    expect(
      boxes.meta.get('yearClose/2026'),
      unorderedEquals(['reports', 'leave', 'holidays']),
    );
  });

  testWidgets('PDF önce önizlenir, sonra paylaşılır', (tester) async {
    await pump(tester);
    await choose(tester, 'PDF (önizle ve paylaş)');
    expect(find.text('2026 yıllık özet'), findsOneWidget);
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('pdf-page-0')), findsOneWidget);
    expect(services.calls, ['pdfPages']);
    await tester.tap(find.widgetWithText(FloatingActionButton, 'Paylaş'));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    expect(services.calls, ['pdfPages', 'sharePdf:nobet-istatistik-2026.pdf']);
    expect(String.fromCharCodes(services.lastPdf!.take(5)), '%PDF-');
  });

  testWidgets('kişi karnesi: kişi seçilir, PDF paylaşılır', (tester) async {
    await pump(tester);
    await choose(tester, 'Kişi karnesi (önizle ve paylaş)');
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
    await choose(tester, 'PDF (önizle ve paylaş)');
    expect(services.calls, isEmpty);
    expect(find.text('2025 için paylaşılacak liste yok.'), findsOneWidget);
  });
}
