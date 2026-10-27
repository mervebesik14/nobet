import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:nobet_listesi/app.dart';
import 'package:nobet_listesi/shared/notification_service.dart';

import 'helpers.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
  });

  tearDown(() => Hive.close());

  testWidgets('Alt navigasyonda 5 sekme var ve geçiş çalışıyor', (
    tester,
  ) async {
    final boxes = await openTestBoxes();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...boxOverrides(boxes),
          notificationServiceProvider.overrideWithValue(
            FakeNotificationService(),
          ),
        ],
        child: const NobetApp(),
      ),
    );

    final nav = find.byType(NavigationBar);
    for (final label in [
      'Kişiler',
      'Ay Planı',
      'Tatiller',
      'İstatistik',
      'Ayarlar',
    ]) {
      expect(
        find.descendant(of: nav, matching: find.text(label)),
        findsOneWidget,
      );
    }

    await tester.tap(find.descendant(of: nav, matching: find.text('Ayarlar')));
    await tester.pumpAndSettle();

    expect(tester.widget<NavigationBar>(nav).selectedIndex, 4);

    await tester.tap(
      find.descendant(of: nav, matching: find.text('İstatistik')),
    );
    await tester.pumpAndSettle();
    expect(tester.widget<NavigationBar>(nav).selectedIndex, 3);
    expect(find.byTooltip('Eski listeleri gir'), findsOneWidget);
  });
}
