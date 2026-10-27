import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:nobet_listesi/data/hive_boxes.dart';
import 'package:nobet_listesi/data/holiday_repository.dart';
import 'package:nobet_listesi/features/month/month_page.dart';
import 'package:nobet_listesi/models/models.dart';
import 'package:nobet_listesi/shared/platform_services.dart';
import 'package:nobet_listesi/shared/providers.dart';

import '../../helpers.dart';

/// Ekim 2026 için sorunsuz ekip: 7 hemşire, 4 tekniker.
const _team = [
  Person(id: 'n1', name: 'Ayşe', role: Role.nurse),
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
  Person(id: 'x', name: 'Pasif', role: Role.nurse, isActive: false),
];

void main() {
  late HiveBoxes boxes;

  setUpAll(() => initializeDateFormatting('tr_TR'));

  setUp(() async {
    boxes = await openTestBoxes();
    await HolidayRepository(boxes.holidays, boxes.meta).ensureYearSeeded(2026);
  });

  tearDown(() => Hive.close());

  Future<void> seed(List<Person> people, [MonthPlan? plan]) async {
    for (final p in people) {
      await boxes.people.put(p.id, p);
    }
    if (plan != null) await boxes.monthPlans.put(plan.key, plan);
  }

  final services = FakePlatformServices();

  Future<void> pumpPage(WidgetTester tester, {DateTime? today}) async {
    tester.view.physicalSize = const Size(1200, 5200);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...boxOverrides(boxes),
          todayProvider.overrideWithValue(today ?? DateTime(2026, 10, 11)),
          platformServicesProvider.overrideWithValue(services),
        ],
        child: const MaterialApp(home: MonthPage()),
      ),
    );
  }

  testWidgets('kişi yoksa yönlendirir; ay planını oluşturur', (tester) async {
    await pumpPage(tester);

    expect(find.text('Ekim 2026'), findsOneWidget);
    expect(find.textContaining('Aktif kişi yok'), findsOneWidget);
    expect(boxes.monthPlans.get('2026-10'), isNotNull);
    expect(find.textContaining('Hiç aktif hemşire yok'), findsOneWidget);
  });

  testWidgets('aktif kişiler gruplu, istenmeyen gün sayısıyla; sorun yok', (
    tester,
  ) async {
    await seed(
      _team,
      const MonthPlan(
        year: 2026,
        month: 10,
        unavailableDays: {
          'n1': [3, 14],
        },
      ),
    );
    await pumpPage(tester);

    expect(find.text('Hemşireler'), findsOneWidget);
    expect(find.text('Radyoloji Teknikerleri'), findsOneWidget);
    expect(find.text('Pasif'), findsNothing);
    expect(find.text('2 gün istemiyor'), findsOneWidget);
    expect(find.text('İstenmeyen gün yok'), findsNWidgets(10));
    expect(find.text('Uygunluk kontrolü: sorun görünmüyor'), findsOneWidget);
  });

  testWidgets('fazla mesai anahtarı kaydedilir ve satırda görünür', (
    tester,
  ) async {
    await seed(_team);
    await pumpPage(tester);

    await tester.tap(find.text('Ali'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fazla mesai istiyor'));
    await tester.pumpAndSettle();
    expect(boxes.monthPlans.get('2026-10')!.wantsOvertime('t1'), isTrue);

    await tester.pageBack();
    await tester.pumpAndSettle();
    // Ay Planı satırında işaret görünür.
    expect(find.text('Fazla mesai istiyor'), findsOneWidget);

    // Kapatınca kalkar.
    await tester.tap(find.text('Ali'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fazla mesai istiyor'));
    await tester.pumpAndSettle();
    expect(boxes.monthPlans.get('2026-10')!.wantsOvertime('t1'), isFalse);
  });

  testWidgets('takvimden gün seçilir/kaldırılır ve kaydedilir', (tester) async {
    await seed(_team);
    await pumpPage(tester);

    await tester.tap(find.text('Ali'));
    await tester.pumpAndSettle();
    expect(find.text('Ekim 2026 · Radyoloji Teknikeri'), findsOneWidget);
    // 29 Ekim tatil olarak listelenir.
    expect(find.text('29 Ekim: Cumhuriyet Bayramı'), findsOneWidget);

    await tester.tap(find.text('14'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('20'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Seçili: 2 gün'), findsOneWidget);
    expect(boxes.monthPlans.get('2026-10')!.unavailableDaysOf('t1'), [14, 20]);

    await tester.tap(find.text('14'));
    await tester.pumpAndSettle();
    expect(boxes.monthPlans.get('2026-10')!.unavailableDaysOf('t1'), [20]);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('1 gün istemiyor'), findsOneWidget);
  });

  testWidgets('Temizle tüm günleri kaldırır, kayıt silinir', (tester) async {
    await seed(
      _team,
      const MonthPlan(
        year: 2026,
        month: 10,
        unavailableDays: {
          't1': [1, 2, 3],
        },
      ),
    );
    await pumpPage(tester);

    await tester.tap(find.text('Ali'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Temizle'));
    await tester.pumpAndSettle();

    final plan = boxes.monthPlans.get('2026-10')!;
    expect(plan.unavailableDays.containsKey('t1'), isFalse);
    expect(find.text('Temizle'), findsNothing);
  });

  testWidgets('Yıllık izin aralık olarak eklenir ve satırda görünür', (
    tester,
  ) async {
    await seed(_team);
    await pumpPage(tester);

    await tester.tap(find.text('Ali'));
    await tester.pumpAndSettle();
    // Üç sekme var.
    expect(find.text('İstenmeyen günler'), findsOneWidget);
    expect(find.text('Yıllık izin'), findsOneWidget);
    expect(find.text('Şua izni'), findsOneWidget);

    await tester.tap(find.text('Yıllık izin'));
    await tester.pumpAndSettle();
    expect(find.textContaining('gereken saatten düşülür'), findsOneWidget);
    // Fazla mesai anahtarı yıllık izin sekmesinde yok.
    expect(find.text('Fazla mesai istiyor'), findsNothing);

    // 6–9 aralığı: başlangıç ve bitişe dokun, sonra "İzin ekle".
    await tester.tap(find.text('6'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('9'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('İzin ekle'));
    await tester.pumpAndSettle();

    expect(boxes.monthPlans.get('2026-10')!.annualLeaveOf('t1'), [6, 7, 8, 9]);
    // İzin günleri istenmeyen günlere karışmaz.
    expect(boxes.monthPlans.get('2026-10')!.unavailableDaysOf('t1'), isEmpty);
    // Aralık özeti çipi görünür.
    expect(find.text('6–9 Ekim'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('4 gün yıllık izin'), findsOneWidget);
  });

  testWidgets('Şua izni ayrı sekmede tutulur, yıllık izinden bağımsız', (
    tester,
  ) async {
    await seed(_team);
    await pumpPage(tester);

    await tester.tap(find.text('Ali'));
    await tester.pumpAndSettle();
    // Kaydırılabilir sekme çubuğunda üçüncü sekmeyi görünür yap.
    await tester.drag(find.byType(TabBar), const Offset(-300, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Şua izni'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('10'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('12'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('İzin ekle'));
    await tester.pumpAndSettle();

    final plan = boxes.monthPlans.get('2026-10')!;
    expect(plan.radiationLeaveOf('t1'), [10, 11, 12]);
    expect(plan.annualLeaveOf('t1'), isEmpty);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('3 gün şua izni'), findsOneWidget);
  });

  testWidgets('Rapor sekmesinden aralık eklenir ve satırda görünür', (
    tester,
  ) async {
    await seed(_team);
    await pumpPage(tester);

    await tester.tap(find.text('Ali'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(TabBar), const Offset(-400, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rapor'));
    await tester.pumpAndSettle();
    expect(find.textContaining('raporun bittiği'), findsOneWidget);

    await tester.tap(find.text('13'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('14'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('İzin ekle'));
    await tester.pumpAndSettle();

    final plan = boxes.monthPlans.get('2026-10')!;
    expect(plan.sickLeaveOf('t1'), [13, 14]);
    expect(plan.annualLeaveOf('t1'), isEmpty);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('2 gün rapor'), findsOneWidget);
  });

  testWidgets('kişi takviminde ay değiştirilir; izin iki aya taşabilir', (
    tester,
  ) async {
    await seed(_team);
    await pumpPage(tester);

    await tester.tap(find.text('Ali'));
    await tester.pumpAndSettle();
    expect(find.text('Ekim 2026'), findsOneWidget);

    // İstenmeyen günler sekmesinde Kasım'a geçilip gün seçilir.
    await tester.tap(find.byTooltip('Sonraki ay'));
    await tester.pumpAndSettle();
    expect(find.text('Kasım 2026'), findsOneWidget);
    await tester.tap(find.text('9'));
    await tester.pumpAndSettle();
    expect(boxes.monthPlans.get('2026-11')!.unavailableDaysOf('t1'), [9]);

    // Yıllık izin: 26 Ekim'de başlar, Kasım'a geçilip 6 Kasım'da biter.
    await tester.tap(find.byTooltip('Önceki ay'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Yıllık izin'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('26'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Başlangıç: 26 Ekim'), findsOneWidget);
    await tester.tap(find.byTooltip('Sonraki ay'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('6'));
    await tester.pumpAndSettle();
    expect(find.text('Seçilen: 26 Ekim – 6 Kasım'), findsOneWidget);
    await tester.tap(find.text('İzin ekle'));
    await tester.pumpAndSettle();

    expect(boxes.monthPlans.get('2026-10')!.annualLeaveOf('t1'), [
      26, 27, 28, 29, 30, 31, //
    ]);
    expect(boxes.monthPlans.get('2026-11')!.annualLeaveOf('t1'), [
      1, 2, 3, 4, 5, 6, //
    ]);
    // Kasım'ın istenmeyen günü korunur.
    expect(boxes.monthPlans.get('2026-11')!.unavailableDaysOf('t1'), [9]);
    expect(find.textContaining('Diğer ayın günleri'), findsOneWidget);
  });

  testWidgets('İzin çipi silinince o aralık kaldırılır', (tester) async {
    await seed(
      _team,
      const MonthPlan(
        year: 2026,
        month: 10,
        unavailableDays: {
          't1': [1],
        },
        annualLeave: {
          't1': [5, 6, 7],
        },
      ),
    );
    await pumpPage(tester);

    await tester.tap(find.text('Ali'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Yıllık izin'));
    await tester.pumpAndSettle();
    // Kayıtlı aralık çipi görünür; silgisine dokun.
    expect(find.text('5–7 Ekim'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.cancel).first);
    await tester.pumpAndSettle();

    final plan = boxes.monthPlans.get('2026-10')!;
    expect(plan.annualLeave.containsKey('t1'), isFalse);
    // İstenmeyen gün korunur.
    expect(plan.unavailableDaysOf('t1'), [1]);
  });

  testWidgets('Nöbet günleri sekmesi yalnızca sorumlu hemşirede', (
    tester,
  ) async {
    await seed([
      ..._team,
      const Person(
        id: 'c',
        name: 'Sorumlu',
        role: Role.nurse,
        isChargeNurse: true,
      ),
    ]);
    await pumpPage(tester);

    // Sıradan hemşirede sekme yok.
    await tester.tap(find.text('Ayşe'));
    await tester.pumpAndSettle();
    expect(find.text('Nöbet günleri'), findsNothing);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Sorumlu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nöbet günleri'));
    await tester.pumpAndSettle();
    expect(find.textContaining('bu günlere nöbet yazılır'), findsOneWidget);
    expect(find.text('Fazla mesai istiyor'), findsNothing);

    await tester.tap(find.text('5'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('12'));
    await tester.pumpAndSettle();
    expect(boxes.monthPlans.get('2026-10')!.requestedShiftsOf('c'), [5, 12]);

    // Aynı gün istenmeyen yapılınca nöbet günlerinden çıkar. (Sekme çubuğu
    // kaydı; ilk sekme görünsün diye geri kaydırılır.)
    await tester.drag(find.byType(TabBar), const Offset(300, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('İstenmeyen günler'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('5'));
    await tester.pumpAndSettle();
    final plan = boxes.monthPlans.get('2026-10')!;
    expect(plan.unavailableDaysOf('c'), [5]);
    expect(plan.requestedShiftsOf('c'), [12]);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('1 gün nöbet seçildi'), findsOneWidget);
  });

  testWidgets('uygun tekniker kalmayan gün uyarı olarak görünür', (
    tester,
  ) async {
    await seed(
      _team,
      const MonthPlan(
        year: 2026,
        month: 10,
        unavailableDays: {
          't1': [14],
          't2': [14],
          't3': [14],
        },
      ),
    );
    await pumpPage(tester);

    await tester.tap(find.text('Deniz'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('14'));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.text('Uygunluk kontrolü: 1 sorun'), findsOneWidget);
    expect(
      find.text('• 14 Ekim: uygun radyoloji teknikeri yok.'),
      findsOneWidget,
    );
  });

  testWidgets('kilitli ayda günler değiştirilemez', (tester) async {
    await seed(
      _team,
      const MonthPlan(
        year: 2026,
        month: 10,
        isLocked: true,
        unavailableDays: {
          't1': [5],
        },
      ),
    );
    await pumpPage(tester);
    expect(find.text('Bu ay kilitli.'), findsOneWidget);

    await tester.tap(find.text('Ali'));
    await tester.pumpAndSettle();
    expect(find.textContaining('değiştirilemez'), findsOneWidget);
    expect(find.text('Temizle'), findsNothing);

    await tester.tap(find.text('14'));
    await tester.pumpAndSettle();
    expect(boxes.monthPlans.get('2026-10')!.unavailableDaysOf('t1'), [5]);
  });

  testWidgets('ay değişince o ayın planı gelir', (tester) async {
    await seed(
      _team,
      const MonthPlan(
        year: 2026,
        month: 11,
        unavailableDays: {
          'n2': [1, 2, 3, 4],
        },
      ),
    );
    await pumpPage(tester);
    expect(find.text('4 gün istemiyor'), findsNothing);

    await tester.tap(find.byTooltip('Sonraki ay'));
    await tester.pumpAndSettle();
    expect(find.text('Kasım 2026'), findsOneWidget);
    expect(find.text('4 gün istemiyor'), findsOneWidget);
  });

  group('yedek hatırlatması', () {
    testWidgets('kişi yokken çıkmaz', (tester) async {
      await pumpPage(tester);
      expect(find.text('Yedek al'), findsNothing);
    });

    testWidgets('hiç yedek yoksa çıkar; "Yedek al" paylaşır ve kapanır', (
      tester,
    ) async {
      await seed(_team);
      await pumpPage(tester);
      expect(find.textContaining('Henüz yedek alınmadı'), findsOneWidget);

      await tester.tap(find.text('Yedek al'));
      await tester.pumpAndSettle();
      expect(services.calls.last, 'shareFile:nobet-yedek-2026-10-11.json');
      expect(find.text('Yedek al'), findsNothing);
      expect(boxes.meta.get('lastBackupAt'), startsWith('2026-10-11'));
    });

    testWidgets('14 günü geçmiş yedek hatırlatılır; "Sonra" susturur', (
      tester,
    ) async {
      await seed(_team);
      await boxes.meta.put(
        'lastBackupAt',
        DateTime(2026, 9, 20).toIso8601String(),
      );
      await pumpPage(tester);
      expect(find.text('21 gündür yedek alınmadı.'), findsOneWidget);

      await tester.tap(find.text('Sonra'));
      await tester.pumpAndSettle();
      expect(find.text('Yedek al'), findsNothing);
      expect(boxes.meta.get('backupSnoozedUntil'), startsWith('2026-10-18'));
    });

    testWidgets('yakın tarihli yedek varsa çıkmaz', (tester) async {
      await seed(_team);
      await boxes.meta.put(
        'lastBackupAt',
        DateTime(2026, 10, 5).toIso8601String(),
      );
      await pumpPage(tester);
      expect(find.text('Yedek al'), findsNothing);
    });
  });

  group('ay başı hatırlatması', () {
    final reminder = find.byKey(const ValueKey('next-month-reminder'));

    Future<void> seedTeam() async {
      await seed(_team);
      // Yedek kartı karışmasın.
      await boxes.meta.put(
        'lastBackupAt',
        DateTime(2026, 10, 15).toIso8601String(),
      );
    }

    testWidgets('ayın 16sından önce çıkmaz', (tester) async {
      await seedTeam();
      await pumpPage(tester, today: DateTime(2026, 10, 15));
      expect(reminder, findsNothing);
    });

    testWidgets('16sından itibaren çıkar; gelecek aya geçirir', (tester) async {
      await seedTeam();
      await boxes.monthPlans.put(
        '2026-11',
        const MonthPlan(
          year: 2026,
          month: 11,
          unavailableDays: {
            'n1': [3, 4],
            'n2': [10],
          },
        ),
      );
      await pumpPage(tester, today: DateTime(2026, 10, 16));
      expect(reminder, findsOneWidget);
      expect(
        find.textContaining('Kasım listesi henüz oluşturulmadı'),
        findsOneWidget,
      );
      expect(find.textContaining('2 kişinin girişi var'), findsOneWidget);

      await tester.tap(find.text('Kasım ayına geç'));
      await tester.pumpAndSettle();
      expect(find.text('Kasım 2026'), findsOneWidget);
      expect(reminder, findsNothing);
    });

    testWidgets('ayarda seçilen günden itibaren çıkar', (tester) async {
      await seedTeam();
      await boxes.meta.put('monthReminderDay', 8);
      await pumpPage(tester, today: DateTime(2026, 10, 8));
      expect(reminder, findsOneWidget);
    });

    testWidgets('ayarda seçilen günden önce çıkmaz', (tester) async {
      await seedTeam();
      await boxes.meta.put('monthReminderDay', 8);
      await pumpPage(tester, today: DateTime(2026, 10, 7));
      expect(reminder, findsNothing);
    });

    testWidgets('"Başladım" o ayın kartını kapatır', (tester) async {
      await seedTeam();
      await pumpPage(tester, today: DateTime(2026, 10, 20));
      await tester.tap(
        find.descendant(of: reminder, matching: find.text('Başladım')),
      );
      await tester.pumpAndSettle();
      expect(reminder, findsNothing);
      expect(boxes.meta.get('monthReminderStartedMonths'), ['2026-11']);
      expect(
        find.text('Kasım hatırlatması kapandı. Kolay gelsin!'),
        findsOneWidget,
      );
    });

    testWidgets('"Sonra" 3 gün susturur', (tester) async {
      await seedTeam();
      await pumpPage(tester, today: DateTime(2026, 10, 20));
      await tester.tap(
        find.descendant(of: reminder, matching: find.text('Sonra')),
      );
      await tester.pumpAndSettle();
      expect(reminder, findsNothing);
      expect(
        boxes.meta.get('nextMonthReminderSnoozedUntil'),
        startsWith('2026-10-23'),
      );
    });

    testWidgets('gelecek ayın listesi varsa çıkmaz', (tester) async {
      await seedTeam();
      await boxes.monthPlans.put(
        '2026-11',
        const MonthPlan(
          year: 2026,
          month: 11,
          assignments: {
            1: DayAssignment(day: 1, nurseIds: ['n1', 'n2'], techId: 't1'),
          },
        ),
      );
      await pumpPage(tester, today: DateTime(2026, 10, 25));
      expect(reminder, findsNothing);
    });
  });
}
