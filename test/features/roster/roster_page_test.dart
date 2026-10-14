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

  testWidgets('uygunluk uyarısı izin günlerini de hesaba katar', (
    tester,
  ) async {
    // 18 Ekim'de tüm teknikerler şua izninde: istenmeyen gün yok ama
    // uygun tekniker de yok.
    await boxes.monthPlans.put(
      '2026-10',
      const MonthPlan(
        year: 2026,
        month: 10,
        radiationLeave: {
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
        sickLeave: {
          'n3': [15, 16],
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
    expect(inTable('R.'), findsNWidgets(2));
    for (final d in [15, 16]) {
      expect(plan.assignments[d]!.includes('n3'), isFalse);
    }
  });

  testWidgets('yıllık izin öncesi iş günü ve sonrası hafta sonu nöbetsiz', (
    tester,
  ) async {
    // 9 Ekim Cuma. n1 yıllık izni 8–9; 10 Cmt ve 11 Paz da nöbete kapalı,
    // ilk nöbet en erken 12 Pazartesi.
    await boxes.monthPlans.put(
      '2026-10',
      const MonthPlan(
        year: 2026,
        month: 10,
        annualLeave: {
          'n1': [8, 9],
        },
      ),
    );
    await pumpMonthPage(tester);
    await tester.tap(find.text('Listeyi Oluştur'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hemşire + Tekniker'));
    await tester.pumpAndSettle();

    final plan = saved();
    // İzinden önceki iş günü, izin günleri ve izinden sonraki hafta sonu
    // n1'e kapalı.
    for (final d in [7, 8, 9, 10, 11]) {
      expect(plan.assignments[d]!.includes('n1'), isFalse, reason: 'gün $d');
    }
  });

  testWidgets('sorumlu hemşire: mesai günlerinde tabloda 7A görünür', (
    tester,
  ) async {
    await boxes.people.put(
      'c',
      const Person(
        id: 'c',
        name: 'Sorumlu Hemşire',
        role: Role.nurse,
        isChargeNurse: true,
      ),
    );
    await pumpMonthPage(tester);
    await tester.tap(find.text('Listeyi Oluştur'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hemşire + Tekniker'));
    await tester.pumpAndSettle();

    // Yeterli hemşire var: sorumlu hemşire nöbet almaz.
    final plan = saved();
    expect(plan.assignments.values.any((a) => a.includes('c')), isFalse);

    // Ekim 2026'da 21 mesai günü (29 Ekim tatil hariç, 28 arife dahil):
    // her birinde tabloda bir "7A"; nöbeti olmadığı için hepsi sorumluda.
    Finder inTable(String t) =>
        find.descendant(of: find.byType(RosterTable), matching: find.text(t));
    expect(inTable('7A'), findsNWidgets(21));
    // Özette görevi ve 7A sütunu.
    expect(find.text('Sorumlu hemşire'), findsOneWidget);
    expect(find.text('7A\ngün'), findsOneWidget);
  });

  testWidgets('sorumlu hemşire seçilen nöbet günlerine yazılır', (
    tester,
  ) async {
    await boxes.people.put(
      'c',
      const Person(
        id: 'c',
        name: 'Sorumlu Hemşire',
        role: Role.nurse,
        isChargeNurse: true,
      ),
    );
    await boxes.monthPlans.put(
      '2026-10',
      const MonthPlan(
        year: 2026,
        month: 10,
        requestedShifts: {
          'c': [7, 21],
        },
      ),
    );
    await pumpMonthPage(tester);
    await tester.tap(find.text('Listeyi Oluştur'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hemşire + Tekniker'));
    await tester.pumpAndSettle();

    final days = {
      for (final a in saved().assignments.values)
        if (a.includes('c')) a.day,
    };
    expect(days, {7, 21});
    // Seçilen nöbet günleri sıfırlamada korunur.
    await tester.tap(find.byTooltip('Listeyi sıfırla'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Sıfırla'));
    await tester.pumpAndSettle();
    expect(saved().requestedShiftsOf('c'), [7, 21]);
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

    await tester.tap(find.byTooltip('Listeyi sıfırla'));
    await tester.pumpAndSettle();
    // Önce vazgeç: değişmez.
    await tester.tap(find.text('Vazgeç'));
    await tester.pumpAndSettle();
    expect(saved().hasRoster, isTrue);

    await tester.tap(find.byTooltip('Listeyi sıfırla'));
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

  testWidgets('kilitli liste de sıfırlanır; kilit açılır', (tester) async {
    await pumpMonthPage(tester);
    await tester.tap(find.text('Listeyi Oluştur'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hemşire + Tekniker'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Kilitle'));
    await tester.pumpAndSettle();
    expect(saved().isLocked, isTrue);

    await tester.tap(find.byTooltip('Listeyi sıfırla'));
    await tester.pumpAndSettle();
    expect(find.textContaining('kilidi de açılır'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Sıfırla'));
    await tester.pumpAndSettle();

    expect(saved().hasRoster, isFalse);
    expect(saved().isLocked, isFalse);
    expect(find.text('Listeyi Oluştur'), findsOneWidget);
  });

  testWidgets('Ay Planı ekranından da liste sıfırlanır', (tester) async {
    await pumpMonthPage(tester);
    // Liste yokken buton görünmez.
    expect(find.text('Listeyi sıfırla'), findsNothing);
    await tester.tap(find.text('Listeyi Oluştur'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hemşire + Tekniker'));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Listeyi sıfırla'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Sıfırla'));
    await tester.pumpAndSettle();

    expect(saved().hasRoster, isFalse);
    expect(find.text('Listeyi Oluştur'), findsOneWidget);
    expect(find.text('Listeyi sıfırla'), findsNothing);
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
