import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:nobet_listesi/data/hive_boxes.dart';
import 'package:nobet_listesi/data/holiday_repository.dart';
import 'package:nobet_listesi/features/roster/roster_page.dart';
import 'package:nobet_listesi/data/roster_history_repository.dart';
import 'package:nobet_listesi/features/month/month_plan_controller.dart';
import 'package:nobet_listesi/models/models.dart';
import 'package:nobet_listesi/shared/providers.dart';

import '../../helpers.dart';

const _nurses = ['Ayşe', 'Banu', 'Cemile', 'Derya', 'Elif', 'Fatma', 'Gül'];
const _techs = ['Ali', 'Burak', 'Can', 'Deniz'];

/// 7 hemşire + 4 tekniker; Hale (n7) yedek hemşire, hiç nöbeti yok. 5
/// Ekim'den itibaren pasif: testler ona 3 Ekim'de nöbet verir; pasif günler
/// boşluğu kestiği için ay sonu boşluk uyarısı çıkmaz, kurala uygun aday
/// kalır.
final _people = [
  for (var i = 0; i < _nurses.length; i++)
    Person(id: 'n$i', name: _nurses[i], role: Role.nurse),
  Person(
    id: 'n7',
    name: 'Hale',
    role: Role.nurse,
    inactiveFrom: DateTime(2026, 10, 5),
  ),
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
    Map<String, List<int>> annualLeave = const {},
    bool locked = false,
  }) async {
    await boxes.monthPlans.put(
      '2026-10',
      MonthPlan(
        year: 2026,
        month: 10,
        assignments: _rotation(),
        unavailableDays: unavailable,
        annualLeave: annualLeave,
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
          rosterRunnerProvider.overrideWithValue((g) async => g.generate()),
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
    expect(find.text('Diğer kural ihlalleri (2)'), findsOneWidget);
    expect(find.text('• Derya 7 ve 8 Ekim art arda nöbette.'), findsOneWidget);
    // Ayşe'nin 7 Ekim nöbeti kalkınca 3 ile 10 arası 6 gün boş kalır.
    expect(
      find.text('• Ayşe 3 ve 10 Ekim arasında 6 gün boş (en fazla 5).'),
      findsOneWidget,
    );
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

  testWidgets('ihlaller ayrı kutularda; boş günler en üstte', (tester) async {
    await pumpRoster(
      tester,
      unavailable: {
        'n7': [3],
      },
    );

    // İstemediği güne atama: Hale 3 Ekim'de Ayşe'nin yerine.
    await tester.tap(cell('n7', 3));
    await tester.pumpAndSettle();
    await tester.tap(inSheet('Ayşe yerine ata'));
    await tester.pumpAndSettle();
    // Boş gün: 4 Ekim'de Banu'nun nöbeti kaldırılır.
    await tester.tap(cell('n1', 4));
    await tester.pumpAndSettle();
    await tester.tap(inSheet('Nöbeti kaldır'));
    await tester.pumpAndSettle();

    expect(find.text('Boş günler (1)'), findsOneWidget);
    expect(find.text('• 4 Ekim: 1 hemşire eksik.'), findsOneWidget);
    // Boş günün altında kimin neden yazılamadığı açıklanır; nöbeti
    // kaldırılan Banu kurallara uyduğu için yeniden eklenebilir.
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('violations-missing')),
        matching: find.textContaining(
          'Banu: kurallara uyuyor, elle eklenebilir',
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.text('İzinli / istemediği günde çalışanlar (1)'),
      findsOneWidget,
    );
    expect(find.text('Diğer kural ihlalleri (1)'), findsNothing);
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('violations-missing'))).dy,
      lessThan(
        tester
            .getTopLeft(find.byKey(const ValueKey('violations-unavailable')))
            .dy,
      ),
    );
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

  testWidgets('yıllık izin öncesi güne atanan kişi için doğru neden yazar', (
    tester,
  ) async {
    // 16 Ekim Cuma nöbetçisinin 19 Ekim Pazartesi yıllık izni başlıyor:
    // son nöbeti Perşembe olmalı, Cuma kapalı ama "istemediği gün" değil.
    final id = _rotation()[16]!.nurseIds.first;
    await pumpRoster(
      tester,
      annualLeave: {
        id: [19, 20],
      },
    );
    final name = boxes.people.get(id)!.name;
    expect(
      find.textContaining('$name yıllık izninden hemen önceki güne (16 Ekim)'),
      findsOneWidget,
    );
    expect(find.textContaining('$name istemediği'), findsNothing);
    expect(
      find.textContaining('İzinli / istemediği günde çalışanlar'),
      findsOneWidget,
    );
  });

  testWidgets('Bu güne ata: dolu günde en uygun kişinin yerine atar', (
    tester,
  ) async {
    await pumpRoster(tester);

    // 3 Ekim: Gül (n6) ve Ayşe (n0); ikisinin de 9 nöbeti var, ilki seçilir.
    await tester.tap(cell('n7', 3));
    await tester.pumpAndSettle();
    expect(inSheet('Bu güne ata'), findsOneWidget);
    expect(inSheet('Gül yerine atanır.'), findsOneWidget);
    expect(inSheet('Koltuk seç'), findsOneWidget);

    await tester.tap(inSheet('Bu güne ata'));
    await tester.pumpAndSettle();
    expect(sheet(), findsNothing);
    final nurses = saved().assignments[3]!.nurseIds;
    expect(nurses, containsAll(['n7', 'n0']));
    expect(nurses, isNot(contains('n6')));
  });

  testWidgets('Bu güne ata: boş koltuk varsa oraya atar', (tester) async {
    await pumpRoster(tester);

    // Önce 3 Ekim'de Ayşe'nin nöbetini kaldır: bir hemşire koltuğu boşalır.
    await tester.tap(cell('n0', 3));
    await tester.pumpAndSettle();
    await tester.tap(inSheet('Nöbeti kaldır'));
    await tester.pumpAndSettle();
    expect(saved().assignments[3]!.nurseIds, ['n6']);

    await tester.tap(cell('n7', 3));
    await tester.pumpAndSettle();
    expect(inSheet('Boş koltuğa atanır.'), findsOneWidget);
    await tester.tap(inSheet('Bu güne ata'));
    await tester.pumpAndSettle();
    expect(saved().assignments[3]!.nurseIds, containsAll(['n6', 'n7']));
    expect(find.text('Kural ihlali yok'), findsOneWidget);
  });

  testWidgets('uzun bas → takas modu; ikinci nöbete dokununca takas', (
    tester,
  ) async {
    await pumpRoster(tester);

    await tester.longPress(cell('n0', 3));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Başka bir nöbetle takas et'));
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

  testWidgets('basılı tut → Değiştir: elle başkasını yaz', (tester) async {
    await pumpRoster(tester);

    await tester.longPress(cell('n0', 3));
    await tester.pumpAndSettle();
    expect(find.text('Değiştir'), findsOneWidget);
    await tester.tap(find.text('Değiştir'));
    await tester.pumpAndSettle();
    expect(inSheet('Nöbeti kaldır'), findsOneWidget);
    await tester.tap(inSheet('Hale'));
    await tester.pumpAndSettle();
    expect(saved().assignments[3]!.nurseIds, ['n6', 'n7']);

    // Boş hücrede basılı tutmak doğrudan atama seçeneklerini açar.
    await tester.longPress(cell('n0', 4));
    await tester.pumpAndSettle();
    expect(inSheet('Bu güne ata'), findsOneWidget);
  });

  testWidgets('takas yapısal olarak olamıyorsa açıklar', (tester) async {
    await pumpRoster(tester);

    await tester.longPress(cell('n0', 3));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Başka bir nöbetle takas et'));
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
    await tester.tap(find.text('Başka bir nöbetle takas et'));
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
    expect(find.text('Başka bir nöbetle takas et'), findsNothing);
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
    expect((hale.cells[7].child as Text).data, '24'); // çalışılan saat
  });

  group('değişiklik geçmişi', () {
    testWidgets('bildirimdeki "Geri al" son değişikliği geri alır', (
      tester,
    ) async {
      await pumpRoster(tester);
      await tester.tap(cell('n0', 3));
      await tester.pumpAndSettle();
      await tester.tap(inSheet('Hale'));
      await tester.pumpAndSettle();
      expect(saved().assignments[3]!.nurseIds, ['n6', 'n7']);
      expect(find.text('Değişiklik kaydedildi.'), findsOneWidget);

      await tester.tap(find.text('Geri al'));
      await tester.pumpAndSettle();
      expect(saved().assignments, _rotation());
      expect(boxes.history.get('2026-10'), isNull);
    });

    testWidgets('geçmiş ekranı kayıtları gösterir; eskisine dönülür', (
      tester,
    ) async {
      await pumpRoster(tester);
      // 1) Ayşe yerine Hale (3 Ekim), 2) Banu'nun 4 Ekim nöbeti kaldırılır.
      await tester.tap(cell('n0', 3));
      await tester.pumpAndSettle();
      await tester.tap(inSheet('Hale'));
      await tester.pumpAndSettle();
      await tester.tap(cell('n1', 4));
      await tester.pumpAndSettle();
      await tester.tap(inSheet('Nöbeti kaldır'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Değişiklik geçmişi'));
      await tester.pumpAndSettle();
      expect(find.text('• 3 Ekim: Ayşe yerine Hale'), findsOneWidget);
      expect(find.text('• 4 Ekim: Banu çıkarıldı'), findsOneWidget);
      // En yeni üstte.
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('edit-1'))).dy,
        lessThan(tester.getTopLeft(find.byKey(const ValueKey('edit-0'))).dy),
      );

      // İlk değişikliğe kadar geri: ikisi de geri alınır.
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('edit-0')),
          matching: find.text('Geri al'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('sonraki 1 değişiklik'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Geri al'));
      await tester.pumpAndSettle();

      expect(saved().assignments, _rotation());
      expect(find.text('Bu ay için değişiklik kaydı yok.'), findsOneWidget);
    });

    testWidgets('kilitli ayda geri alınamaz', (tester) async {
      await pumpRoster(tester);
      await tester.tap(cell('n0', 3));
      await tester.pumpAndSettle();
      await tester.tap(inSheet('Hale'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Kilitle'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Değişiklik geçmişi'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Liste kilitli'), findsOneWidget);
      final button = tester.widget<TextButton>(
        find
            .ancestor(
              of: find.descendant(
                of: find.byKey(const ValueKey('edit-0')),
                matching: find.text('Geri al'),
              ),
              matching: find.byWidgetPredicate((w) => w is TextButton),
            )
            .first,
      );
      expect(button.onPressed, isNull);
    });
  });

  testWidgets('kurallara göre düzelt: ihlal giderilir, geri alınabilir', (
    tester,
  ) async {
    // Ayşe (n0) 3 Ekim'i istemiyor ama listede o gün nöbetçi.
    await pumpRoster(
      tester,
      unavailable: {
        'n0': [3],
      },
    );
    expect(saved().assignments[3]!.nurseIds, contains('n0'));
    // Kural ihlali yokken düğme görünmez; burada var.
    await tester.tap(find.text('Kurallara göre düzelt'));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();

    final fixed = saved();
    expect(fixed.assignments[3]!.nurseIds, isNot(contains('n0')));
    expect(fixed.assignments[3]!.nurseIds, hasLength(2));
    expect(find.textContaining('nöbet değişti.'), findsOneWidget);
    expect(
      RosterHistoryRepository(boxes.history).load(2026, 10).last.title,
      'Kurallara göre düzeltildi',
    );

    await tester.tap(find.text('Geri al'));
    await tester.pumpAndSettle();
    expect(saved().assignments, _rotation());
  });

  testWidgets('serbest düzenleme: dokununca ekler / siler, kural engellemez', (
    tester,
  ) async {
    await pumpRoster(tester);
    await tester.tap(find.text('Serbest düzenleme'));
    await tester.pumpAndSettle();

    // 3 Ekim dolu (Gül, Ayşe); Hale üçüncü hemşire olarak eklenir.
    await tester.tap(cell('n7', 3));
    await tester.pumpAndSettle();
    expect(sheet(), findsNothing);
    expect(saved().assignments[3]!.nurseIds, ['n6', 'n0', 'n7']);
    expect(find.text('Hale 3 Ekim nöbetine yazıldı.'), findsOneWidget);
    expect(find.text('• 3 Ekim: 1 fazla hemşire yazılı.'), findsOneWidget);

    // Ayşe'nin nöbetine dokununca silinir.
    await tester.tap(cell('n0', 3));
    await tester.pumpAndSettle();
    expect(saved().assignments[3]!.nurseIds, ['n6', 'n7']);
    expect(find.text('Ayşe 3 Ekim nöbetinden çıkarıldı.'), findsOneWidget);

    // Kapatınca dokunma yine seçenekleri açar.
    await tester.tap(find.text('Serbest düzenleme'));
    await tester.pumpAndSettle();
    await tester.tap(cell('n0', 3));
    await tester.pumpAndSettle();
    expect(sheet(), findsOneWidget);
  });

  testWidgets('basılı tut → Sil: nöbet doğrudan silinir', (tester) async {
    await pumpRoster(tester);
    await tester.longPress(cell('n0', 3));
    await tester.pumpAndSettle();
    expect(find.text('Sil'), findsOneWidget);
    await tester.tap(find.text('Sil'));
    await tester.pumpAndSettle();
    expect(saved().assignments[3]!.nurseIds, ['n6']);
    expect(find.text('Ayşe 3 Ekim nöbetinden çıkarıldı.'), findsOneWidget);
  });

  testWidgets(
    'serbest düzenlemede basılı tut → Değiştir silmez, seçenek açar',
    (tester) async {
      await pumpRoster(tester);
      await tester.tap(find.text('Serbest düzenleme'));
      await tester.pumpAndSettle();
      await tester.longPress(cell('n0', 3));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Değiştir'));
      await tester.pumpAndSettle();
      expect(inSheet('Yerine atanabilecekler'), findsOneWidget);
      expect(saved().assignments[3]!.nurseIds, ['n6', 'n0']);
      await tester.tap(inSheet('Hale'));
      await tester.pumpAndSettle();
      expect(saved().assignments[3]!.nurseIds, ['n6', 'n7']);
    },
  );

  testWidgets('kural bozan ekleme: uyarı verir, istenirse yine de yapar', (
    tester,
  ) async {
    await pumpRoster(
      tester,
      unavailable: {
        'n7': [3],
      },
    );
    await tester.tap(find.text('Serbest düzenleme'));
    await tester.pumpAndSettle();

    await tester.tap(cell('n7', 3));
    await tester.pumpAndSettle();
    expect(find.text('Kural ihlali'), findsOneWidget);
    expect(
      find.text(
        '• Hale istemediği güne (3 Ekim) atandı.\n\nYine de yapılsın mı?',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Vazgeç'));
    await tester.pumpAndSettle();
    expect(saved().assignments[3]!.nurseIds, ['n6', 'n0']);

    await tester.tap(cell('n7', 3));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Yine de yap'));
    await tester.pumpAndSettle();
    expect(saved().assignments[3]!.nurseIds, ['n6', 'n0', 'n7']);
    expect(find.text('Hale 3 Ekim nöbetine yazıldı.'), findsOneWidget);
  });

  testWidgets('kural bozan takas: uyarı verir, istenirse yine de yapar', (
    tester,
  ) async {
    await pumpRoster(tester);
    // Ayşe 3 ↔ Fatma 6: Ayşe 6–7, Fatma 2–3 art arda olur.
    await tester.longPress(cell('n0', 3));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Başka bir nöbetle takas et'));
    await tester.pumpAndSettle();
    await tester.tap(cell('n5', 6));
    await tester.pumpAndSettle();
    expect(find.text('Kural ihlali'), findsOneWidget);
    expect(find.textContaining('art arda nöbette'), findsOneWidget);
    await tester.tap(find.text('Yine de yap'));
    await tester.pumpAndSettle();
    expect(saved().assignments[3]!.nurseIds, contains('n5'));
    expect(saved().assignments[6]!.nurseIds, contains('n0'));
  });

  testWidgets('kurala uyan değişiklikte uyarı penceresi çıkmaz', (
    tester,
  ) async {
    await pumpRoster(tester);
    await tester.tap(find.text('Serbest düzenleme'));
    await tester.pumpAndSettle();
    await tester.tap(cell('n0', 3));
    await tester.pumpAndSettle();
    expect(find.text('Kural ihlali'), findsNothing);
    expect(saved().assignments[3]!.nurseIds, ['n6']);
  });

  group('basılı tut → 7A / 16B', () {
    // Sorumlu hemşire: mesai günlerinde 7A var (Ekim 2026: 7 Çarşamba,
    // 8 Perşembe).
    Future<void> addCharge() => boxes.people.put(
      'c',
      const Person(
        id: 'c',
        name: 'Sorumlu',
        role: Role.nurse,
        isChargeNurse: true,
      ),
    );

    testWidgets("24 nöbeti 7A'ya çevrilir (tek değişiklik)", (tester) async {
      await addCharge();
      await pumpRoster(tester);
      // Ayşe 7 Ekim Çarşamba 24 nöbette.
      await tester.longPress(cell('n0', 7));
      await tester.pumpAndSettle();
      await tester.tap(find.text("7A'ya çevir"));
      await tester.pumpAndSettle();
      expect(find.text('Kural ihlali'), findsNothing);
      expect(saved().assignments[7]!.nurseIds, isNot(contains('n0')));
      expect(saved().dayShiftOverrides, {7: 'n0'});
      expect(find.text("Ayşe 7 Ekim 24 yerine 7A'ya yazıldı."), findsOneWidget);
      expect(
        find.descendant(of: cell('n0', 7), matching: find.text('7A')),
        findsOneWidget,
      );
      // Geri al ikisini birden geri alır.
      await tester.tap(find.text('Geri al'));
      await tester.pumpAndSettle();
      expect(saved().assignments[7]!.nurseIds, contains('n0'));
      expect(saved().dayShiftOverrides, isEmpty);
    });

    testWidgets('boş hücreye 7A yazılır; nöbet ertesiyse uyarır', (
      tester,
    ) async {
      await addCharge();
      await pumpRoster(tester);
      // Banu 7 Ekim nöbette → 8 Ekim nöbet ertesi.
      await tester.longPress(cell('n1', 8));
      await tester.pumpAndSettle();
      expect(find.text('24 nöbet yaz'), findsOneWidget);
      await tester.tap(find.text('7A yaz'));
      await tester.pumpAndSettle();
      expect(find.text('Kural ihlali'), findsOneWidget);
      expect(find.textContaining('Banu 8 Ekim nöbet ertesi.'), findsOneWidget);
      await tester.tap(find.text('Yine de yap'));
      await tester.pumpAndSettle();
      expect(saved().dayShiftOverrides, {8: 'n1'});
      expect(saved().assignments, _rotation());
    });

    testWidgets("tekniker 16B'ye ve geri 24'e çevrilir", (tester) async {
      await pumpRoster(tester);
      // Ali 4 Ekim 24 nöbette.
      await tester.longPress(cell('t0', 4));
      await tester.pumpAndSettle();
      expect(find.text("7A'ya çevir"), findsNothing);
      await tester.tap(find.text("16B'ye çevir"));
      await tester.pumpAndSettle();
      expect(saved().assignments[4]!.techId, isNull);
      expect(saved().assignments[4]!.tech16bId, 't0');
      expect(find.text("Ali 4 Ekim 16B'ye yazıldı."), findsOneWidget);
      expect(
        find.descendant(of: cell('t0', 4), matching: find.text('16B')),
        findsOneWidget,
      );

      await tester.longPress(cell('t0', 4));
      await tester.pumpAndSettle();
      await tester.tap(find.text("24'e çevir"));
      await tester.pumpAndSettle();
      expect(saved().assignments[4]!.techId, 't0');
      expect(saved().assignments[4]!.tech16bId, isNull);
      expect(find.text("Ali 4 Ekim 24'e yazıldı."), findsOneWidget);
    });

    testWidgets('boş tekniker hücresine 16B yazılır', (tester) async {
      await pumpRoster(tester);
      // 4 Ekim: Ali 24'te; Burak'a 16B.
      await tester.longPress(cell('t1', 4));
      await tester.pumpAndSettle();
      await tester.tap(find.text('16B yaz'));
      await tester.pumpAndSettle();
      expect(saved().assignments[4]!.techId, 't0');
      expect(saved().assignments[4]!.tech16bId, 't1');
    });
  });

  group('basılı tut → teknikere 7A', () {
    // Ekim 2026: 5 Pzt, 6 Sal; 3–4 hafta sonu. Can (t2): 2, 6, 10…;
    // Burak (t1): 1, 5, 9…
    testWidgets('boş hücreye 7A yazılır ve kaldırılır', (tester) async {
      await pumpRoster(tester);
      await tester.longPress(cell('t2', 5));
      await tester.pumpAndSettle();
      expect(find.text('16B yaz'), findsOneWidget);
      await tester.tap(find.text('7A yaz'));
      await tester.pumpAndSettle();
      expect(find.text('Kural ihlali'), findsNothing);
      expect(saved().techDayShifts, {
        't2': [5],
      });
      expect(find.text("Can 5 Ekim 7A'ya yazıldı."), findsOneWidget);
      expect(
        find.descendant(of: cell('t2', 5), matching: find.text('7A')),
        findsOneWidget,
      );

      await tester.longPress(cell('t2', 5));
      await tester.pumpAndSettle();
      expect(find.text('7A yaz'), findsNothing);
      await tester.tap(find.text("7A'yı kaldır"));
      await tester.pumpAndSettle();
      expect(saved().techDayShifts, isEmpty);
      expect(find.text('Can 5 Ekim 7A kaldırıldı.'), findsOneWidget);
    });

    testWidgets("nöbet 7A'ya çevrilir; geri al ikisini geri alır", (
      tester,
    ) async {
      await pumpRoster(tester);
      await tester.longPress(cell('t2', 6));
      await tester.pumpAndSettle();
      await tester.tap(find.text("7A'ya çevir"));
      await tester.pumpAndSettle();
      expect(saved().assignments[6]!.techId, isNull);
      expect(saved().techDayShifts, {
        't2': [6],
      });
      expect(
        find.text("Can 6 Ekim nöbet yerine 7A'ya yazıldı."),
        findsOneWidget,
      );
      await tester.tap(find.text('Geri al'));
      await tester.pumpAndSettle();
      expect(saved().assignments[6]!.techId, 't2');
      expect(saved().techDayShifts, isEmpty);
    });

    testWidgets('24 nöbet ertesi 7A uyarır; hafta sonu seçenek yok', (
      tester,
    ) async {
      await pumpRoster(tester);
      // Burak 5 Ekim 24 nöbette → 6 Ekim nöbet ertesi.
      await tester.longPress(cell('t1', 6));
      await tester.pumpAndSettle();
      await tester.tap(find.text('7A yaz'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Burak 6 Ekim nöbet ertesi.'), findsOneWidget);
      await tester.tap(find.text('Vazgeç'));
      await tester.pumpAndSettle();
      expect(saved().techDayShifts, isEmpty);

      // 4 Ekim Pazar: 7A yok.
      await tester.longPress(cell('t3', 4));
      await tester.pumpAndSettle();
      expect(find.text('16B yaz'), findsOneWidget);
      expect(find.text('7A yaz'), findsNothing);
    });

    testWidgets("7A'lı güne 24 yazılınca 7A düşer", (tester) async {
      // 5 Ekim'in tekniker koltuğu boş.
      final rotation = _rotation();
      await boxes.monthPlans.put(
        '2026-10',
        MonthPlan(
          year: 2026,
          month: 10,
          assignments: {
            ...rotation,
            5: DayAssignment(day: 5, nurseIds: rotation[5]!.nurseIds),
          },
          techDayShifts: const {
            't2': [5],
          },
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
          child: const MaterialApp(home: RosterPage(freeEdit: true)),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: cell('t2', 5), matching: find.text('7A')),
        findsOneWidget,
      );
      // Serbest düzenlemede 7A hücresine dokununca 24 yazılır, 7A düşer
      // (Can 6'sında da nöbetçi: art arda uyarısı onaylanır).
      await tester.tap(cell('t2', 5));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Yine de yap'));
      await tester.pumpAndSettle();
      expect(saved().assignments[5]!.personIds, contains('t2'));
      expect(saved().techDayShifts, isEmpty);
    });
  });
}
