import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:nobet_listesi/data/hive_boxes.dart';
import 'package:nobet_listesi/data/holiday_repository.dart';
import 'package:nobet_listesi/features/roster/roster_page.dart';
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

  Future<void> choose(WidgetTester tester, String item) async {
    await tester.tap(find.byTooltip('Paylaş'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(item));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
  }

  bool isPdf(List<int>? bytes) =>
      bytes != null && String.fromCharCodes(bytes.take(5)) == '%PDF-';

  testWidgets('PDF olarak paylaş', (tester) async {
    await pump(tester);
    await choose(tester, 'PDF olarak paylaş');
    expect(services.calls, ['sharePdf:nobet-listesi-2026-10.pdf']);
    expect(isPdf(services.lastPdf), isTrue);
  });

  testWidgets('Görsel (PNG) olarak paylaş', (tester) async {
    await pump(tester);
    await choose(tester, 'Görsel (PNG) olarak paylaş');
    expect(services.calls, ['pdfToPng', 'shareFile:nobet-listesi-2026-10.png']);
    expect(services.sharedFiles.single.mime, 'image/png');
    expect(isPdf(services.lastPdf), isTrue);
  });

  testWidgets('Yazdır', (tester) async {
    await pump(tester);
    await choose(tester, 'Yazdır');
    expect(services.calls, ['printPdf:Ekim 2026 Nöbet Listesi']);
  });
}
