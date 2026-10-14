import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:nobet_listesi/data/hive_boxes.dart';
import 'package:nobet_listesi/data/holiday_repository.dart';
import 'package:nobet_listesi/features/month/month_page.dart';
import 'package:nobet_listesi/features/month/month_plan_controller.dart';
import 'package:nobet_listesi/models/models.dart';
import 'package:nobet_listesi/shared/providers.dart';

import '../../helpers.dart';

final _people = [
  for (var i = 1; i <= 7; i++)
    Person(id: 'n$i', name: 'Hemşire $i', role: Role.nurse),
  for (var i = 1; i <= 4; i++)
    Person(id: 't$i', name: 'Tekniker $i', role: Role.radiologyTech),
];

/// Eylül 2026: n1 ve n5 tek günlerde (15'er), n6 ve n7 çift günlerde
/// (14'er), son gün (30) n2, n3 ve t1. n4 hiç tutmamış.
MonthPlan _september({bool locked = false}) => MonthPlan(
  year: 2026,
  month: 9,
  isLocked: locked,
  assignments: {
    for (var d = 1; d <= 30; d++)
      d: DayAssignment(
        day: d,
        nurseIds: d == 30
            ? const ['n2', 'n3']
            : d.isOdd
            ? const ['n1', 'n5']
            : const ['n6', 'n7'],
        techId: d == 30 ? 't1' : 't${d % 4 + 1}',
      ),
  },
);

void main() {
  late HiveBoxes boxes;

  setUpAll(() => initializeDateFormatting('tr_TR'));

  setUp(() async {
    boxes = await openTestBoxes();
    await HolidayRepository(boxes.holidays, boxes.meta).ensureYearSeeded(2026);
    for (final p in _people) {
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
          rosterRunnerProvider.overrideWithValue((g) async => g.generate()),
        ],
        child: const MaterialApp(home: MonthPage()),
      ),
    );
  }

  testWidgets('geçmiş ay açılınca kilitlenir; kilit açılabilir', (
    tester,
  ) async {
    await boxes.monthPlans.put('2026-09', _september());
    await pumpMonthPage(tester);

    await tester.tap(find.byTooltip('Önceki ay'));
    await tester.pumpAndSettle();
    expect(find.text('Eylül 2026'), findsOneWidget);
    expect(find.text('Geçmiş ay: liste salt okunur.'), findsOneWidget);
    expect(find.text('Listeyi Gör'), findsOneWidget);
    expect(boxes.monthPlans.get('2026-09')!.isLocked, isTrue);

    await tester.tap(find.text('Kilidi aç'));
    await tester.pumpAndSettle();
    expect(boxes.monthPlans.get('2026-09')!.isLocked, isFalse);

    // Başka aya gidip dönünce bu oturumda yeniden kilitlenmez.
    await tester.tap(find.byTooltip('Sonraki ay'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Önceki ay'));
    await tester.pumpAndSettle();
    expect(find.text('Geçmiş ay: liste salt okunur.'), findsNothing);
    expect(boxes.monthPlans.get('2026-09')!.isLocked, isFalse);
  });

  testWidgets('içinde bulunulan ay ve listesiz geçmiş ay kilitlenmez', (
    tester,
  ) async {
    await boxes.monthPlans.put(
      '2026-10',
      MonthPlan(year: 2026, month: 10, assignments: _september().assignments),
    );
    await pumpMonthPage(tester);
    expect(boxes.monthPlans.get('2026-10')!.isLocked, isFalse);

    await tester.tap(find.byTooltip('Önceki ay'));
    await tester.pumpAndSettle();
    expect(boxes.monthPlans.get('2026-09')!.isLocked, isFalse);
  });

  testWidgets('oluştururken önceki ay devri ve yıl içi toplam kullanılır', (
    tester,
  ) async {
    await boxes.monthPlans.put('2026-09', _september(locked: true));
    await pumpMonthPage(tester);

    await tester.tap(find.text('Listeyi Oluştur'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hemşire + Tekniker'));
    await tester.pumpAndSettle();

    final october = boxes.monthPlans.get('2026-10')!;
    expect(october.assignments.length, 31);

    // Eylül 30'un nöbetçileri 1 Ekim'de yok.
    expect(
      october.assignments[1]!.personIds.toSet().intersection({
        'n2',
        'n3',
        't1',
      }),
      isEmpty,
    );

    // 62 / 7: biri 8 tutar; o kişi Eylül'de çok tutanlardan biri olmalı,
    // Eylül'de hiç tutmayan n4 değil.
    final counts = {
      for (var i = 1; i <= 7; i++)
        'n$i': october.assignments.values
            .where((a) => a.nurseIds.contains('n$i'))
            .length,
    };
    final eight = counts.entries.where((e) => e.value == 8).map((e) => e.key);
    expect(eight, hasLength(1));
    expect({'n1', 'n5', 'n6', 'n7'}, contains(eight.single));
    expect(counts['n4'], 9);
  });

  testWidgets('Yıllık Özet: dahil aylar ve kişi başı toplamlar', (
    tester,
  ) async {
    await boxes.monthPlans.put('2026-09', _september(locked: true));
    await pumpMonthPage(tester);
    await tester.tap(find.text('Listeyi Oluştur'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hemşire + Tekniker'));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Yıllık Özet'));
    await tester.pumpAndSettle();
    expect(find.text('2026'), findsOneWidget);
    expect(find.text('Dahil aylar: Eylül, Ekim'), findsOneWidget);

    final table = tester.widget<DataTable>(find.byType(DataTable));
    final n1 = table.rows.firstWhere(
      (r) => (r.cells.first.child as Text).data == 'Hemşire 1',
    );
    String cell(DataRow r, int i) => (r.cells[i].child as Text).data!;
    final october = boxes.monthPlans.get('2026-10')!;
    final n1October = october.assignments.values
        .where((a) => a.nurseIds.contains('n1'))
        .length;
    expect(cell(n1, 2), '2'); // ay sayısı
    expect(cell(n1, 3), '${15 + n1October}'); // toplam nöbet
    // Resmi tatil nöbeti: Eylül'de tam gün tatil yok, Ekim'de yalnız 29 Ekim.
    final n1Holiday = october.assignments[29]!.nurseIds.contains('n1') ? 1 : 0;
    expect(cell(n1, 5), '$n1Holiday'); // resmi tatil nöbeti
    expect(cell(n1, 6), '0'); // dini bayram nöbeti
    expect(cell(n1, 8), '${(15 + n1October) * 24}'); // çalışılan saat

    await tester.tap(find.byTooltip('Önceki yıl'));
    await tester.pumpAndSettle();
    expect(find.text('Bu yıl için oluşturulmuş liste yok.'), findsOneWidget);
    expect(find.byType(DataTable), findsNothing);
  });
}
