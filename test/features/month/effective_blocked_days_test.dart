import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:nobet_listesi/data/hive_boxes.dart';
import 'package:nobet_listesi/data/holiday_repository.dart';
import 'package:nobet_listesi/features/month/month_plan_controller.dart';
import 'package:nobet_listesi/models/models.dart';
import 'package:nobet_listesi/shared/providers.dart';

import '../../helpers.dart';

/// effectiveBlockedDaysProvider: nöbet dağıtımında kişi başı engellenen
/// günleri (istenmeyen + izinler + yıllık izin sonrası iş gününe kadar)
/// doğru üretiyor mu?
void main() {
  late HiveBoxes boxes;

  setUpAll(() => initializeDateFormatting('tr_TR'));

  setUp(() async {
    boxes = await openTestBoxes();
    await HolidayRepository(boxes.holidays, boxes.meta).ensureYearSeeded(2026);
  });

  tearDown(() => Hive.close());

  ProviderContainer container() {
    final c = ProviderContainer(
      overrides: [
        ...boxOverrides(boxes),
        todayProvider.overrideWithValue(DateTime(2026, 10, 11)),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  test('yıllık izin Cuma bitince hafta sonu da kapanır; şua izni kapanmaz', () {
    // n1 yıllık izin 8–9 (9 Cuma): 10 Cmt, 11 Paz da kapalı.
    // n2 şua izni 8–9: yalnızca izin günleri kapalı.
    boxes.monthPlans.put(
      '2026-10',
      const MonthPlan(
        year: 2026,
        month: 10,
        annualLeave: {
          'n1': [8, 9],
        },
        radiationLeave: {
          'n2': [8, 9],
        },
      ),
    );
    final blocked = container().read(effectiveBlockedDaysProvider);
    expect(blocked['n1'], [8, 9, 10, 11]);
    expect(blocked['n2'], [8, 9]);
  });

  test('istenmeyen günler ve izinler birlikte engellenir', () {
    boxes.monthPlans.put(
      '2026-10',
      const MonthPlan(
        year: 2026,
        month: 10,
        unavailableDays: {
          'n1': [1],
        },
        annualLeave: {
          'n1': [9],
        },
      ),
    );
    final blocked = container().read(effectiveBlockedDaysProvider);
    // 1 istenmeyen, 9 izin, 10-11 izin sonrası hafta sonu.
    expect(blocked['n1'], [1, 9, 10, 11]);
  });
}
