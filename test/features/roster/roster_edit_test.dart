import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:nobet_listesi/data/hive_boxes.dart';
import 'package:nobet_listesi/data/holiday_repository.dart';
import 'package:nobet_listesi/features/roster/roster_page.dart';
import 'package:nobet_listesi/models/models.dart';
import 'package:nobet_listesi/shared/providers.dart';

import '../../helpers.dart';

const _nurses = ['Ayşe', 'Banu', 'Cemile', 'Derya', 'Elif', 'Fatma', 'Gül'];
const _techs = ['Ali', 'Burak', 'Can', 'Deniz'];

/// 7 hemşire + 4 tekniker; Hale (n7) yedek hemşire, hiç nöbeti yok.
final _people = [
  for (var i = 0; i < _nurses.length; i++)
    Person(id: 'n$i', name: _nurses[i], role: Role.nurse),
  const Person(id: 'n7', name: 'Hale', role: Role.nurse),
  for (var i = 0; i < _techs.length; i++)
    Person(id: 't$i', name: _techs[i], role: Role.radiologyTech),
];

/// Kurala uygun dönüşüm: d günü hemşireler (2d, 2d+1) mod 7, tekniker d mod 4.
/// Ör. Ayşe (n0): 3, 7, 10...; Banu: 4, 7, 11; Derya: 1, 5, 8;
/// Gül: 3, 6, 10; Ali (t0): 4, 8, 12...
Map<int, DayAssignment> _rotation() => {
  for (var d = 1; d <= 31; d++)
    d: DayAssignment(
      day: d,
      nurseIds: ['n${(2 * d) % 7}', 'n${(2 * d + 1) % 7}'],
      techId: 't${d % 4}',
    ),
};

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

  Future<void> pumpRoster(
    WidgetTester tester, {
    Map<String, List<int>> unavailable = const {},
    bool locked = false,
  }) async {
    await boxes.monthPlans.put(
      '2026-10',
      MonthPlan(
        year: 2026,
        month: 10,
        assignments: _rotation(),
        unavailableDays: unavailable,
        isLocked: locked,
        seed: 1,
      ),
    );
    tester.view.physicalSize = const Size(3400, 4000);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...boxOverrides(boxes),
          todayProvider.overrideWithValue(DateTime(2026, 10, 11)),
        ],
        child: const MaterialApp(home: RosterPage()),
      ),
    );
  }

  MonthPlan saved() => boxes.monthPlans.get('2026-10')!;
  Finder cell(String id, int day) => find.byKey(ValueKey('cell-$id-$day'));
  Finder sheet() => find.byType(BottomSheet);
  Finder inSheet(String text) =>
      find.descendant(of: sheet(), matching: find.text(text));

  Color? cellColor(WidgetTester tester, String id, int day) {
    final container = tester.widget<Container>(
      find
          .descendant(of: cell(id, day), matching: find.byType(Container))
          .first,
    );
    return (container.decoration as BoxDecoration?)?.color;
  }

  testWidgets('başlangıçta kural ihlali yok', (tester) async {
    await pumpRoster(tester);
    expect(find.text('Kural ihlali yok'), findsOneWidget);
  });

  testWidgets('nöbete dokun: uygun aday üstte, seçince değişir', (
    tester,
  ) async {
    await pumpRoster(tester);

    await tester.tap(cell('n0', 3));
    await tester.pumpAndSettle();
    expect(inSheet('Ayşe · 3 Ekim Cumartesi'), findsOneWidget);
    expect(inSheet('Nöbeti kaldır'), findsOneWidget);
    expect(inSheet('Yerine atanabilecekler'), findsOneWidget);

    // Hale kurala uygun → adaylar arasında ilk sırada, uyarısız.
    final tiles = tester
        .widgetList<ListTile>(
          find.descendant(of: sheet(), matching: find.byType(ListTile)),
        )
        .toList();
    final titles = [for (final t in tiles) (t.title as Text?)?.data];
    expect(titles.indexOf('Hale'), titles.indexOf('Nöbeti kaldır') + 1);
    // Diğerleri uyarılı: Banu 4'ünde nöbetçi.
    expect(
      find.descendant(
        of: sheet(),
        matching: find.text('Banu 3 ve 4 Ekim art arda nöbette.'),
      ),
      findsOneWidget,
    );

    await tester.tap(inSheet('Hale'));
    await tester.pumpAndSettle();

    expect(saved().assignments[3]!.nurseIds, ['n6', 'n7']);
    expect(find.text('Kural ihlali yok'), findsOneWidget);
  });

  testWidgets('kural bozan seçim: ihlal listesi ve renkli hücreler', (
    tester,
  ) async {
    await pumpRoster(tester);
    final normal = cellColor(tester, 'n3', 8);

    await tester.tap(cell('n0', 7));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: sheet(),
        matching: find.textContaining('Derya 7 ve 8 Ekim art arda nöbette.'),
      ),
      findsOneWidget,
    );
    await tester.tap(inSheet('Derya'));
    await tester.pumpAndSettle();

    expect(saved().assignments[7]!.nurseIds, ['n3', 'n1']);
    expect(find.text('Kural ihlalleri (1)'), findsOneWidget);
    expect(find.text('• Derya 7 ve 8 Ekim art arda nöbette.'), findsOneWidget);
    expect(cellColor(tester, 'n3', 8), isNot(normal));
    expect(cellColor(tester, 'n3', 7), cellColor(tester, 'n3', 8));
  });

  testWidgets('nöbeti kaldır → Eksik; boş koltuğa dokunup doldur', (
    tester,
  ) async {
    await pumpRoster(tester);

    await tester.tap(cell('t0', 4));
    await tester.pumpAndSettle();
    await tester.tap(inSheet('Nöbeti kaldır'));
    await tester.pumpAndSettle();

    expect(saved().assignments[4]!.techId, isNull);
    expect(find.text('• 4 Ekim: 1 radyoloji teknikeri eksik.'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('missing-4')));
    await tester.pumpAndSettle();
    expect(inSheet('4 Ekim Pazar · boş koltuk'), findsOneWidget);
    await tester.tap(inSheet('Ali (Radyoloji Teknikeri)'));
    await tester.pumpAndSettle();

    expect(saved().assignments[4]!.techId, 't0');
    expect(find.text('Kural ihlali yok'), findsOneWidget);
  });

  testWidgets('boş hücreye dokun: istemediği güne atanınca uyarı', (
    tester,
  ) async {
    await pumpRoster(
      tester,
      unavailable: {
        'n7': [3],
      },
    );

    await tester.tap(cell('n7', 3));
    await tester.pumpAndSettle();
    expect(inSheet('Bu güne ata'), findsOneWidget);
    expect(inSheet('Gül yerine ata'), findsOneWidget);
    expect(inSheet('Ayşe yerine ata'), findsOneWidget);
    expect(
      find.descendant(
        of: sheet(),
        matching: find.text('Hale istemediği güne (3 Ekim) atandı.'),
      ),
      findsNWidgets(2),
    );

    await tester.tap(inSheet('Ayşe yerine ata'));
    await tester.pumpAndSettle();
    expect(saved().assignments[3]!.nurseIds, ['n6', 'n7']);
    expect(
      find.text('• Hale istemediği güne (3 Ekim) atandı.'),
      findsOneWidget,
    );
  });

  testWidgets('uzun bas → takas modu; ikinci nöbete dokununca takas', (
    tester,
  ) async {
    await pumpRoster(tester);

    await tester.longPress(cell('n0', 3));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Takas: Ayşe – 3 Ekim seçildi.'),
      findsOneWidget,
    );

    // Farklı görev reddedilir, mod sürer.
    await tester.tap(cell('t0', 4));
    await tester.pumpAndSettle();
    expect(
      find.text('Takas yalnızca aynı görevdeki kişiler arasında yapılır.'),
      findsOneWidget,
    );

    await tester.tap(cell('n1', 4));
    await tester.pumpAndSettle();
    expect(saved().assignments[3]!.nurseIds, ['n6', 'n1']);
    expect(saved().assignments[4]!.nurseIds, ['n0', 'n2']);
    expect(
      find.text('Ayşe 3 Ekim ↔ Banu 4 Ekim takas edildi.'),
      findsOneWidget,
    );
    expect(find.textContaining('Takas:'), findsNothing);
  });

  testWidgets('takas yapısal olarak olamıyorsa açıklar', (tester) async {
    await pumpRoster(tester);

    await tester.longPress(cell('n0', 3));
    await tester.pumpAndSettle();
    // Gül 3'ünde zaten nöbetçi.
    await tester.tap(cell('n6', 6));
    await tester.pumpAndSettle();
    expect(
      find.text('Takas yapılamaz: İkinci kişi ilk gün zaten nöbetçi.'),
      findsOneWidget,
    );
    expect(saved().assignments, _rotation());
  });

  testWidgets('takas modu iptal edilebilir', (tester) async {
    await pumpRoster(tester);
    await tester.longPress(cell('n0', 3));
    await tester.pumpAndSettle();
    await tester.tap(find.text('İptal'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Takas:'), findsNothing);

    await tester.tap(cell('n0', 3));
    await tester.pumpAndSettle();
    expect(sheet(), findsOneWidget);
  });

  testWidgets('kilitli listede düzenleme yapılmaz', (tester) async {
    await pumpRoster(tester, locked: true);

    await tester.tap(cell('n0', 3));
    await tester.pumpAndSettle();
    expect(sheet(), findsNothing);
    expect(
      find.text('Liste kilitli; düzenlemek için kilidi açın.'),
      findsOneWidget,
    );

    await tester.longPress(cell('n0', 3));
    await tester.pumpAndSettle();
    expect(find.textContaining('Takas:'), findsNothing);
  });

  testWidgets('özet tablo düzenlemeyle anında güncellenir', (tester) async {
    await pumpRoster(tester);
    final summary = find.byType(DataTable);

    await tester.tap(cell('n0', 3));
    await tester.pumpAndSettle();
    await tester.tap(inSheet('Hale'));
    await tester.pumpAndSettle();

    final table = tester.widget<DataTable>(summary);
    final hale = table.rows.firstWhere(
      (r) => (r.cells.first.child as Text).data == 'Hale',
    );
    expect((hale.cells[2].child as Text).data, '1'); // toplam nöbet
    expect((hale.cells[5].child as Text).data, '24'); // çalışılan saat
  });
}
