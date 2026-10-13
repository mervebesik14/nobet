import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:nobet_listesi/data/hive_boxes.dart';
import 'package:nobet_listesi/data/holiday_repository.dart';
import 'package:nobet_listesi/features/month/month_page.dart';
import 'package:nobet_listesi/features/month/month_plan_controller.dart';
import 'package:nobet_listesi/features/roster/roster_table.dart';
import 'package:nobet_listesi/models/models.dart';
import 'package:nobet_listesi/shared/providers.dart';

import '../../helpers.dart';

const _team = [
  Person(id: 'n1', name: 'Ayşe Yılmaz', role: Role.nurse),
  Person(id: 'n2', name: 'Banu', role: Role.nurse),
  Person(id: 'n3', name: 'Cemile', role: Role.nurse),
  Person(id: 'n4', name: 'Derya', role: Role.nurse),
  Person(id: 'n5', name: 'Elif', role: Role.nurse),
  Person(id: 'n6', name: 'Fatma', role: Role.nurse),
  Person(id: 'n7', name: 'Gül', role: Role.nurse),
  Person(id: 't1', name: 'Ali', role: Role.radiologyTech),
  Person(id: 't2', name: 'Burak', role: Role.radiologyTech),
  Person(id: 't3', name: 'Can', role: Role.radiologyTech),
  Person(id: 't4', name: 'Deniz', role: Role.radiologyTech),
];

void main() {
  late HiveBoxes boxes;

  setUpAll(() => initializeDateFormatting('tr_TR'));

  setUp(() async {
    boxes = await openTestBoxes();
    await HolidayRepository(boxes.holidays, boxes.meta).ensureYearSeeded(2026);
    for (final p in _team) {
      await boxes.people.put(p.id, p);
    }
  });

  tearDown(() => Hive.close());

  Future<void> pumpMonthPage(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 3200);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...boxOverrides(boxes),
          todayProvider.overrideWithValue(DateTime(2026, 10, 11)),
          // Testte isolate yerine aynı iş parçacığında, az denemeyle.
          rosterRunnerProvider.overrideWithValue((g) async => g.generate()),
        ],
        child: const MaterialApp(home: MonthPage()),
      ),
    );
  }

  MonthPlan saved() => boxes.monthPlans.get('2026-10')!;

  testWidgets('Listeyi Oluştur: liste kaydedilir ve tablo + özet açılır', (
    tester,
  ) async {
    await pumpMonthPage(tester);

    await tester.tap(find.text('Listeyi Oluştur'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hemşire + Tekniker'));
    await tester.pumpAndSettle();

    expect(find.text('Ekim 2026 Nöbet Listesi'), findsOneWidget);
    final plan = saved();
    expect(plan.assignments.length, 31);
    expect(plan.seed, isNotNull);
    expect(plan.generatedAt, isNotNull);
    for (final a in plan.assignments.values) {
      expect(a.nurseIds.length, 2);
      expect(a.techId, isNotNull);
    }

    // Tablo: satırlarda kişiler (tabloda ve özette), sütunlarda günler,
    // nöbet olan her hücrede "24": 31 gün × 3 kişi (+1: 24. günün başlığı).
    final table = find.byType(RosterTable);
    Finder inTable(String text) =>
        find.descendant(of: table, matching: find.text(text));
    expect(inTable('Hemşireler'), findsOneWidget);
    expect(inTable('Radyoloji Teknikerleri'), findsOneWidget);
    for (final p in _team) {
      expect(inTable(p.name), findsOneWidget);
    }
    expect(inTable('1'), findsOneWidget);
    expect(inTable('Per'), findsWidgets);
    expect(inTable('31'), findsOneWidget);
    expect(inTable('24'), findsNWidgets(31 * 3 + 1));
    expect(inTable('Eksik'), findsNothing);

    // Ayşe'nin satırındaki "24"ler kayıtlı nöbet sayısıyla aynı.
    final ayseShifts = plan.assignments.values
        .where((a) => a.includes('n1'))
        .length;
    final ayseRowY = tester.getCenter(inTable('Ayşe Yılmaz')).dy;
    final ayseCells = tester
        .widgetList<Text>(inTable('24'))
        .map((w) => find.byWidget(w))
        .where((f) => (tester.getCenter(f).dy - ayseRowY).abs() < 1)
        .where(
          (f) => tester.widget<Text>(f).style?.fontWeight == FontWeight.bold,
        )
        .length;
    expect(ayseCells, ayseShifts);

    // Özet: kişiler, rol ortalamaları, gereken saat.
    expect(find.text('Özet'), findsOneWidget);
    expect(find.text('Ortalama'), findsNWidgets(2));
    expect(find.text('Ayşe Yılmaz'), findsNWidgets(2)); // tablo + özet
    expect(find.text('145'), findsWidgets);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Listeyi Gör'), findsOneWidget);
  });

  testWidgets('uygunluk sorunu varsa sorar; vazgeçince oluşturulmaz', (
    tester,
  ) async {
    await boxes.monthPlans.put(
      '2026-10',
      const MonthPlan(
        year: 2026,
        month: 10,
        unavailableDays: {
          't1': [18],
          't2': [18],
          't3': [18],
          't4': [18],
        },
      ),
    );
    await pumpMonthPage(tester);

    await tester.tap(find.text('Listeyi Oluştur'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hemşire + Tekniker'));
    await tester.pumpAndSettle();
    expect(find.text('Uygunluk sorunları var'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.textContaining(
          '18 Ekim: uygun radyoloji teknikeri yok.',
        ),
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Vazgeç'));
    await tester.pumpAndSettle();
    expect(saved().hasRoster, isFalse);

    await tester.tap(find.text('Listeyi Oluştur'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hemşire + Tekniker'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Yine de dene'));
    await tester.pumpAndSettle();

    expect(find.text('Liste tam kurulamadı'), findsOneWidget);
    expect(
      find.textContaining('18 Ekim: 1 radyoloji teknikeri eksik'),
      findsOneWidget,
    );
    await tester.tap(find.text('Tamam'));
    await tester.pumpAndSettle();

    expect(find.text('Ekim 2026 Nöbet Listesi'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(RosterTable),
        matching: find.text('Eksik'),
      ),
      findsOneWidget,
    );
    expect(
      find.text('• 18 Ekim: 1 radyoloji teknikeri eksik.'),
      findsOneWidget,
    );
    expect(saved().assignments[18]!.techId, isNull);
  });

  testWidgets('kilitle; kilitliyken yeniden oluşturma onay ister', (
    tester,
  ) async {
    await pumpMonthPage(tester);
    await tester.tap(find.text('Listeyi Oluştur'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hemşire + Tekniker'));
    await tester.pumpAndSettle();
    final first = saved();

    await tester.tap(find.byTooltip('Kilitle'));
    await tester.pumpAndSettle();
    expect(saved().isLocked, isTrue);
    expect(find.text('Liste kilitli'), findsOneWidget);

    await tester.tap(find.byTooltip('Yeniden oluştur'));
    await tester.pumpAndSettle();
    expect(find.text('Bu ay kilitli'), findsOneWidget);
    await tester.tap(find.text('Vazgeç'));
    await tester.pumpAndSettle();
    expect(saved().assignments, first.assignments);

    await tester.tap(find.byTooltip('Yeniden oluştur'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Yeniden oluştur'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hemşire + Tekniker'));
    await tester.pumpAndSettle();
    expect(saved().seed, isNot(first.seed));
    expect(saved().isLocked, isTrue);

    await tester.tap(find.byTooltip('Kilidi aç'));
    await tester.pumpAndSettle();
    expect(saved().isLocked, isFalse);
  });

  testWidgets('kilitsiz listede yeniden oluşturma onaysız yeni tohum', (
    tester,
  ) async {
    await pumpMonthPage(tester);
    await tester.tap(find.text('Listeyi Oluştur'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hemşire + Tekniker'));
    await tester.pumpAndSettle();
    final firstSeed = saved().seed;

    await tester.tap(find.byTooltip('Yeniden oluştur'));
    await tester.pumpAndSettle();
    expect(find.text('Bu ay kilitli'), findsNothing);
    await tester.tap(find.text('Hemşire + Tekniker'));
    await tester.pumpAndSettle();
    expect(saved().seed, isNot(firstSeed));
    expect(saved().assignments.length, 31);
  });

  testWidgets('izinli günler tabloda "Y.İ." / "Ş.İ." olarak görünür', (
    tester,
  ) async {
    await boxes.monthPlans.put(
      '2026-10',
      const MonthPlan(
        year: 2026,
        month: 10,
        annualLeave: {
          'n1': [6, 7, 8],
        },
        radiationLeave: {
          'n2': [12, 13],
        },
      ),
    );
    await pumpMonthPage(tester);
    await tester.tap(find.text('Listeyi Oluştur'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hemşire + Tekniker'));
    await tester.pumpAndSettle();

    // İzinli kişiler izin günlerinde nöbete atanmaz (iznin bittiği günden
    // sonra tekrar nöbete girebilir).
    final plan = saved();
    for (final d in [6, 7, 8]) {
      expect(plan.assignments[d]!.includes('n1'), isFalse);
    }
    for (final d in [12, 13]) {
      expect(plan.assignments[d]!.includes('n2'), isFalse);
    }
    // Tabloda her yıllık izin günü "Y.İ.", her şua izni günü "Ş.İ.".
    Finder inTable(String t) =>
        find.descendant(of: find.byType(RosterTable), matching: find.text(t));
    expect(inTable('Y.İ.'), findsNWidgets(3));
    expect(inTable('Ş.İ.'), findsNWidgets(2));
  });

  testWidgets('Listeyi sıfırla: onaylayınca liste silinir, tercihler kalır', (
    tester,
  ) async {
    await boxes.monthPlans.put(
      '2026-10',
      const MonthPlan(
        year: 2026,
        month: 10,
        unavailableDays: {
          'n1': [5],
        },
        annualLeave: {
          'n2': [8],
        },
        overtimeRequests: {'t1'},
      ),
    );
    await pumpMonthPage(tester);
    await tester.tap(find.text('Listeyi Oluştur'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hemşire + Tekniker'));
    await tester.pumpAndSettle();
    expect(saved().hasRoster, isTrue);

    await tester.tap(find.byTooltip('Diğer'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Listeyi sıfırla'));
    await tester.pumpAndSettle();
    // Önce vazgeç: değişmez.
    await tester.tap(find.text('Vazgeç'));
    await tester.pumpAndSettle();
    expect(saved().hasRoster, isTrue);

    await tester.tap(find.byTooltip('Diğer'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Listeyi sıfırla'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Sıfırla'));
    await tester.pumpAndSettle();

    // Liste silinir ama istenmeyen gün, izin ve fazla mesai korunur.
    final plan = saved();
    expect(plan.hasRoster, isFalse);
    expect(plan.generatedAt, isNull);
    expect(plan.seed, isNull);
    expect(plan.unavailableDaysOf('n1'), [5]);
    expect(plan.annualLeaveOf('n2'), [8]);
    expect(plan.wantsOvertime('t1'), isTrue);
    // Ay Planı'na dönülür.
    expect(find.text('Listeyi Oluştur'), findsOneWidget);
  });

  testWidgets('yalnız hemşire: tekniker atanmaz ve listede görünmez', (
    tester,
  ) async {
    await pumpMonthPage(tester);

    await tester.tap(find.text('Listeyi Oluştur'));
    await tester.pumpAndSettle();
    expect(find.text('Liste kimler için?'), findsOneWidget);
    await tester.tap(find.text('Yalnız hemşire'));
    await tester.pumpAndSettle();

    final plan = saved();
    expect(plan.nurseOnly, isTrue);
    expect(plan.assignments.length, 31);
    for (final a in plan.assignments.values) {
      expect(a.nurseIds.length, 2);
      expect(a.techId, isNull); // tekniker atanmadı
    }

    final table = find.byType(RosterTable);
    Finder inTable(String t) =>
        find.descendant(of: table, matching: find.text(t));
    // Hemşireler görünür, Radyoloji Teknikerleri grubu ve teknikerler yok.
    expect(inTable('Hemşireler'), findsOneWidget);
    expect(inTable('Radyoloji Teknikerleri'), findsNothing);
    for (final name in ['Ali', 'Burak', 'Can', 'Deniz']) {
      expect(inTable(name), findsNothing);
    }
    // Tekniker eksikliği ihlal/eksik olarak sayılmaz.
    expect(find.text('Kural ihlali yok'), findsOneWidget);
    expect(inTable('Eksik'), findsNothing);
  });
}
