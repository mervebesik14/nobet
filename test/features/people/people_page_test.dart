import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:nobet_listesi/data/hive_boxes.dart';
import 'package:nobet_listesi/features/people/people_page.dart';
import 'package:nobet_listesi/models/models.dart';

import '../../helpers.dart';

void main() {
  late HiveBoxes boxes;

  setUp(() async {
    boxes = await openTestBoxes();
  });

  tearDown(() => Hive.close());

  Future<void> pumpPage(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: boxOverrides(boxes),
        child: const MaterialApp(home: PeoplePage()),
      ),
    );
  }

  Future<void> seed(List<Person> people) async {
    for (final p in people) {
      await boxes.people.put(p.id, p);
    }
  }

  Finder header(String title) =>
      find.ancestor(of: find.text(title), matching: find.byType(Row));

  testWidgets('boşken yönlendirme mesajı gösterir', (tester) async {
    await pumpPage(tester);
    expect(find.textContaining('Henüz kişi eklenmedi'), findsOneWidget);
  });

  testWidgets('role göre gruplar, sayıları gösterir, pasifler en altta', (
    tester,
  ) async {
    await seed(const [
      Person(id: '1', name: 'Ayşe', role: Role.nurse),
      Person(id: '2', name: 'Fatma', role: Role.nurse),
      Person(id: '3', name: 'Ali', role: Role.radiologyTech),
      Person(id: '4', name: 'Cem', role: Role.nurse, isActive: false),
    ]);
    await pumpPage(tester);

    expect(
      find.descendant(of: header('Hemşireler'), matching: find.text('2')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: header('Radyoloji Teknikerleri'),
        matching: find.text('1'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: header('Pasif'), matching: find.text('1')),
      findsOneWidget,
    );

    // Sıra: Hemşireler (Ayşe, Fatma), Teknikerler (Ali), Pasif (Cem).
    final order = [
      'Ayşe',
      'Fatma',
      'Ali',
      'Cem',
    ].map((n) => tester.getTopLeft(find.text(n)).dy).toList();
    expect(order, [...order]..sort());

    final cemTile = find.ancestor(
      of: find.text('Cem'),
      matching: find.byType(Opacity),
    );
    expect(tester.widget<Opacity>(cemTile).opacity, lessThan(1));
    expect(find.text('Hemşire · pasif'), findsOneWidget);
  });

  testWidgets('+ ile form açılır, kişi eklenir ve kalıcı olur', (tester) async {
    await pumpPage(tester);

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    expect(find.text('Yeni Kişi'), findsOneWidget);

    // Boş ad kabul edilmez.
    await tester.tap(find.text('Kaydet'));
    await tester.pumpAndSettle();
    expect(find.text('Ad boş olamaz.'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField), 'Mehmet Öz');
    await tester.tap(find.text('Radyoloji Teknikeri'));
    await tester.tap(find.text('Kaydet'));
    await tester.pumpAndSettle();

    expect(find.text('Yeni Kişi'), findsNothing);
    expect(find.text('Mehmet Öz'), findsOneWidget);
    final saved = boxes.people.values.single;
    expect(saved.name, 'Mehmet Öz');
    expect(saved.role, Role.radiologyTech);
  });

  testWidgets('sorumlu hemşire işaretlenir; tek kişi olur', (tester) async {
    await seed(const [
      Person(id: '1', name: 'Ayşe', role: Role.nurse, isChargeNurse: true),
    ]);
    await pumpPage(tester);
    expect(find.text('Sorumlu hemşire · 7A'), findsOneWidget);

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'Banu');
    // Önceki sorumlu hemşire uyarıda adıyla görünür.
    expect(find.textContaining('Şu an sorumlu hemşire: Ayşe'), findsOneWidget);
    await tester.tap(find.text('Sorumlu hemşire'));
    await tester.tap(find.text('Kaydet'));
    await tester.pumpAndSettle();

    final banu = boxes.people.values.firstWhere((p) => p.name == 'Banu');
    expect(banu.isChargeNurse, isTrue);
    // Yenisi işaretlenince öncekinin işareti kalkar.
    expect(boxes.people.get('1')!.isChargeNurse, isFalse);
    expect(find.text('Sorumlu hemşire · 7A'), findsOneWidget);
  });

  testWidgets('teknikerde sorumlu hemşire seçeneği yok', (tester) async {
    await pumpPage(tester);
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    expect(find.text('Sorumlu hemşire'), findsOneWidget);
    await tester.tap(find.text('Radyoloji Teknikeri'));
    await tester.pumpAndSettle();
    expect(find.text('Sorumlu hemşire'), findsNothing);
  });

  testWidgets('aynı adla ikinci kişi eklenemez', (tester) async {
    await seed(const [Person(id: '1', name: 'Ayşe', role: Role.nurse)]);
    await pumpPage(tester);

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), ' ayşe ');
    await tester.tap(find.text('Kaydet'));
    await tester.pumpAndSettle();

    expect(find.text('Bu adla bir kişi zaten var.'), findsOneWidget);
    expect(boxes.people.length, 1);
  });

  testWidgets('dokununca düzenlenir, pasif yapılınca alta iner', (
    tester,
  ) async {
    await seed(const [Person(id: '1', name: 'Ayşe', role: Role.nurse)]);
    await pumpPage(tester);

    await tester.tap(find.text('Ayşe'));
    await tester.pumpAndSettle();
    expect(find.text('Kişiyi Düzenle'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField), 'Ayşe Kaya');
    await tester.tap(find.text('Aktif'));
    await tester.tap(find.text('Kaydet'));
    await tester.pumpAndSettle();

    expect(find.text('Ayşe Kaya'), findsOneWidget);
    expect(find.text('Hemşire · pasif'), findsOneWidget);
    expect(boxes.people.get('1')!.isActive, isFalse);
  });

  testWidgets('planda geçen kişinin görevi değiştirilemez', (tester) async {
    await seed(const [Person(id: '1', name: 'Ayşe', role: Role.nurse)]);
    await boxes.monthPlans.put(
      '2026-10',
      const MonthPlan(
        year: 2026,
        month: 10,
        unavailableDays: {
          '1': [3],
        },
      ),
    );
    await pumpPage(tester);

    await tester.tap(find.text('Ayşe'));
    await tester.pumpAndSettle();

    expect(find.textContaining('görevi değiştirilemez'), findsOneWidget);
    final segmented = tester.widget<SegmentedButton<Role>>(
      find.byType(SegmentedButton<Role>),
    );
    expect(segmented.onSelectionChanged, isNull);
  });

  testWidgets('kaydırınca onay sorar, onaylanırsa siler', (tester) async {
    await seed(const [Person(id: '1', name: 'Ayşe', role: Role.nurse)]);
    await pumpPage(tester);

    await tester.drag(find.text('Ayşe'), const Offset(-500, 0));
    await tester.pumpAndSettle();
    expect(find.text('Ayşe silinsin mi?'), findsOneWidget);

    await tester.tap(find.text('Vazgeç'));
    await tester.pumpAndSettle();
    expect(find.text('Ayşe'), findsOneWidget);

    await tester.drag(find.text('Ayşe'), const Offset(-500, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sil'));
    await tester.pumpAndSettle();

    expect(find.text('Ayşe'), findsNothing);
    expect(find.text('Ayşe silindi.'), findsOneWidget);
    expect(boxes.people.isEmpty, isTrue);
  });

  Future<void> seedReferencedAli() async {
    await seed(const [Person(id: '1', name: 'Ali', role: Role.radiologyTech)]);
    await boxes.monthPlans.put(
      '2026-10',
      const MonthPlan(
        year: 2026,
        month: 10,
        assignments: {
          1: DayAssignment(day: 1, nurseIds: ['x', 'y'], techId: '1'),
        },
      ),
    );
  }

  testWidgets('planda geçen kişi kaydırınca doğrudan silinebilir', (
    tester,
  ) async {
    await seedReferencedAli();
    await pumpPage(tester);

    await tester.drag(find.text('Ali'), const Offset(-500, 0));
    await tester.pumpAndSettle();
    expect(find.text('Ali silinsin mi?'), findsOneWidget);
    expect(find.textContaining('"Silinmiş kişi" olarak kalır'), findsOneWidget);

    await tester.tap(find.text('Sil'));
    await tester.pumpAndSettle();

    expect(find.text('Ali'), findsNothing);
    expect(find.text('Ali silindi.'), findsOneWidget);
    expect(boxes.people.get('1'), isNull);
    // Eski liste kaydı yerinde kalır.
    expect(boxes.monthPlans.get('2026-10')!.assignments[1]!.techId, '1');
  });

  testWidgets('planda geçen kişi istenirse pasif yapılır, sonra silinir', (
    tester,
  ) async {
    await seedReferencedAli();
    await pumpPage(tester);

    await tester.drag(find.text('Ali'), const Offset(-500, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pasif yap'));
    await tester.pumpAndSettle();

    expect(find.text('Ali'), findsOneWidget);
    expect(find.text('Radyoloji Teknikeri · pasif'), findsOneWidget);
    expect(find.text('Ali pasif yapıldı.'), findsOneWidget);
    expect(boxes.people.get('1')!.isActive, isFalse);

    // Pasif kişi de silinebilir; bu kez "Pasif yap" seçeneği çıkmaz.
    await tester.drag(find.text('Ali'), const Offset(-500, 0));
    await tester.pumpAndSettle();
    expect(find.text('Pasif yap'), findsNothing);
    await tester.tap(find.text('Sil'));
    await tester.pumpAndSettle();
    expect(boxes.people.get('1'), isNull);
  });

  testWidgets('düzenleme ekranındaki "Kişiyi sil" ile silinir', (tester) async {
    await seedReferencedAli();
    await pumpPage(tester);

    await tester.tap(find.text('Ali'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kişiyi sil'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sil'));
    await tester.pumpAndSettle();

    expect(find.text('Kişiyi Düzenle'), findsNothing);
    expect(find.text('Ali'), findsNothing);
    expect(find.text('Ali silindi.'), findsOneWidget);
    expect(boxes.people.get('1'), isNull);
  });
}
