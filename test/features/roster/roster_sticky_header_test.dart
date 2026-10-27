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

/// 7 hemşire + 4 tekniker, her gün 2 hemşire + 1 tekniker.
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
    for (var i = 0; i < 7; i++) {
      await boxes.people.put(
        'n$i',
        Person(id: 'n$i', name: 'Hemşire $i', role: Role.nurse),
      );
    }
    for (var i = 0; i < 4; i++) {
      await boxes.people.put(
        't$i',
        Person(id: 't$i', name: 'Tekniker $i', role: Role.radiologyTech),
      );
    }
    await boxes.monthPlans.put(
      '2026-10',
      MonthPlan(year: 2026, month: 10, assignments: _rotation()),
    );
  });

  tearDown(() => Hive.close());

  /// Telefon boyutunda (400 × 800) liste ekranı.
  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 2000);
    tester.view.devicePixelRatio = 2.5;
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
    await tester.pumpAndSettle();
  }

  final header = find.byKey(const ValueKey('roster-header'));
  Finder cell(String id, int day) => find.byKey(ValueKey('cell-$id-$day'));
  Finder headerDay(int d) =>
      find.descendant(of: header, matching: find.text('$d'));

  testWidgets('aşağı kaydırınca gün başlıkları üstte sabit kalır', (
    tester,
  ) async {
    await pump(tester);
    final top = tester.getTopLeft(find.byType(CustomScrollView)).dy;
    expect(tester.getTopLeft(header).dy, greaterThan(top));

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -400));
    await tester.pumpAndSettle();
    // Başlık sayfanın en üstüne yapıştı; kişi satırları altından geçer.
    expect(header, findsOneWidget);
    expect(tester.getTopLeft(header).dy, moreOrLessEquals(top));
    expect(headerDay(1), findsOneWidget);
    final headerBottom = tester.getBottomLeft(header).dy;
    expect(tester.getTopLeft(cell('t3', 1)).dy, greaterThan(headerBottom - 1));
  });

  testWidgets('yatay kaydırınca başlık ve tablo birlikte kayar', (
    tester,
  ) async {
    await pump(tester);
    // Gövdeyi sola kaydır: 15. gün başlığı yine 15. gün sütununun üstünde.
    await tester.drag(cell('n0', 3), const Offset(-400, 0));
    await tester.pumpAndSettle();
    expect(
      tester.getCenter(headerDay(15)).dx,
      moreOrLessEquals(tester.getCenter(cell('n0', 15)).dx, epsilon: 0.5),
    );
    // Başlığı sürükleyince de tablo izler.
    await tester.drag(headerDay(15), const Offset(150, 0));
    await tester.pumpAndSettle();
    expect(
      tester.getCenter(headerDay(10)).dx,
      moreOrLessEquals(tester.getCenter(cell('n0', 10)).dx, epsilon: 0.5),
    );
  });
}
