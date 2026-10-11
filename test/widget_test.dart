import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:nobet_listesi/app.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
  });

  testWidgets('Alt navigasyonda 4 sekme var ve geçiş çalışıyor',
      (tester) async {
    await tester.pumpWidget(const ProviderScope(child: NobetApp()));

    final nav = find.byType(NavigationBar);
    for (final label in ['Kişiler', 'Ay Planı', 'Tatiller', 'Ayarlar']) {
      expect(find.descendant(of: nav, matching: find.text(label)),
          findsOneWidget);
    }

    await tester.tap(find.descendant(of: nav, matching: find.text('Ayarlar')));
    await tester.pumpAndSettle();

    final selected = tester.widget<NavigationBar>(nav).selectedIndex;
    expect(selected, 3);
  });
}
