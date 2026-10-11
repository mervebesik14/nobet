import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:nobet_listesi/data/hive_boxes.dart';
import 'package:nobet_listesi/data/holiday_repository.dart';
import 'package:nobet_listesi/features/holidays/holidays_page.dart';
import 'package:nobet_listesi/shared/providers.dart';

import '../../helpers.dart';

void main() {
  late HiveBoxes boxes;

  setUpAll(() => initializeDateFormatting('tr_TR'));

  setUp(() async {
    boxes = await openTestBoxes();
    await HolidayRepository(boxes.holidays, boxes.meta).ensureYearSeeded(2026);
  });

  tearDown(() => Hive.close());

  Future<void> pumpPage(WidgetTester tester, DateTime today) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...boxOverrides(boxes),
          todayProvider.overrideWithValue(today),
        ],
        child: const MaterialApp(home: HolidaysPage()),
      ),
    );
  }

  testWidgets('Ekim 2026: tatiller ve 143,5 saat gereken', (tester) async {
    await pumpPage(tester, DateTime(2026, 10, 11));

    expect(find.text('Ekim 2026'), findsOneWidget);
    expect(find.text('Cumhuriyet Bayramı'), findsOneWidget);
    expect(find.text('Cumhuriyet Bayramı Arifesi'), findsOneWidget);
    expect(find.text('Yarım gün'), findsOneWidget);
    expect(find.text('Bu ay çalışılması gereken: 143,5 saat'), findsOneWidget);
    expect(find.text('20 iş günü + 1 yarım gün × 7 saat'), findsOneWidget);
    expect(find.textContaining('tanımlı değil'), findsNothing);
  });

  testWidgets('ay değiştirilir; tatilsiz ayda mesaj ve 147 saat', (
    tester,
  ) async {
    await pumpPage(tester, DateTime(2026, 10, 11));

    await tester.tap(find.byTooltip('Sonraki ay'));
    await tester.pumpAndSettle();

    expect(find.text('Kasım 2026'), findsOneWidget);
    expect(find.text('Bu ay resmi tatil yok.'), findsOneWidget);
    expect(find.text('Bu ay çalışılması gereken: 147 saat'), findsOneWidget);
  });

  testWidgets('yeni yıla geçince hazır tatiller yüklenir', (tester) async {
    await pumpPage(tester, DateTime(2026, 12, 1));

    await tester.tap(find.byTooltip('Sonraki ay'));
    await tester.pumpAndSettle();

    expect(find.text('Ocak 2027'), findsOneWidget);
    expect(find.text('Yılbaşı'), findsOneWidget);
    expect(
      HolidayRepository(boxes.holidays, boxes.meta).seededYears,
      containsAll([2026, 2027]),
    );
  });

  testWidgets('dini bayram tablosu olmayan yılda uyarı', (tester) async {
    await pumpPage(tester, DateTime(2031, 3, 1));
    await tester.pump();
    expect(find.textContaining('2031 için Ramazan ve Kurban'), findsOneWidget);
  });

  testWidgets('yarım gün işaretlenince gereken saat güncellenir', (
    tester,
  ) async {
    await pumpPage(tester, DateTime(2026, 10, 11));

    // 29 Ekim'i yarım gün yap: 20 tam + 2 yarım = 147 saat.
    await tester.tap(find.byTooltip('Seçenekler').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Yarım gün yap'));
    await tester.pumpAndSettle();

    expect(find.text('Yarım gün'), findsNWidgets(2));
    expect(find.text('Bu ay çalışılması gereken: 147 saat'), findsOneWidget);
    expect(boxes.holidays.get('2026-10-29')!.isHalfDay, isTrue);
  });

  testWidgets('tatil onayla silinir', (tester) async {
    await pumpPage(tester, DateTime(2026, 10, 11));

    await tester.tap(find.byTooltip('Seçenekler').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sil'));
    await tester.pumpAndSettle();
    expect(find.text('Tatil silinsin mi?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Sil'));
    await tester.pumpAndSettle();

    expect(find.text('Cumhuriyet Bayramı'), findsNothing);
    expect(boxes.holidays.get('2026-10-29'), isNull);
    expect(find.text('Bu ay çalışılması gereken: 150,5 saat'), findsOneWidget);
  });

  testWidgets('elle tatil eklenir', (tester) async {
    await pumpPage(tester, DateTime(2026, 10, 11));

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    // Boş form kabul edilmez.
    await tester.tap(find.text('Ekle'));
    await tester.pumpAndSettle();
    expect(find.text('Gün seçin.'), findsOneWidget);
    expect(find.text('Ad boş olamaz.'), findsOneWidget);

    await tester.tap(find.byType(DropdownButtonFormField<int>));
    await tester.pumpAndSettle();
    // Zaten tatil olan günler listede yok.
    expect(find.text('29 Ekim Perşembe'), findsNothing);
    await tester.tap(find.text('2 Ekim Cuma').last);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField), 'Köprü izni');
    await tester.tap(find.text('Ekle'));
    await tester.pumpAndSettle();

    expect(find.text('Köprü izni'), findsOneWidget);
    expect(find.text('Tam gün · elle eklendi'), findsOneWidget);
    final saved = boxes.holidays.get('2026-10-02')!;
    expect(saved.isPredefined, isFalse);
    expect(saved.isHalfDay, isFalse);
    expect(find.text('Bu ay çalışılması gereken: 136,5 saat'), findsOneWidget);
  });
}
