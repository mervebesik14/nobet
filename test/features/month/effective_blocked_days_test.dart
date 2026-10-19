import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:nobet_listesi/data/hive_boxes.dart';
import 'package:nobet_listesi/data/holiday_repository.dart';
import 'package:nobet_listesi/data/month_plan_repository.dart';
import 'package:nobet_listesi/features/month/month_plan_controller.dart';
import 'package:nobet_listesi/logic/block_reason.dart';
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

  test('yıllık izin öncesi/sonrası; şua öncesi iki gün ve dönüşü kapanır', () {
    // n1 yıllık izin 8–9 (Per–Cum): öncesinde 7 Çar, sonrasında 10 Cmt ve
    // 11 Paz da kapalı. n2 şua izni 8–9: önceki iki gün (6, 7), izin günleri
    // ve dönüşte ilk iş gününe kadar (10, 11) kapalı.
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
    final c = container();
    final blocked = c.read(effectiveBlockedDaysProvider);
    expect(blocked['n1'], [7, 8, 9, 10, 11]);
    // Şua: izinden önceki iki gün (6, 7), izin günleri ve dönüşte ilk iş
    // gününe (12 Pazartesi) kadar hafta sonu (10, 11) kapalı.
    expect(blocked['n2'], [6, 7, 8, 9, 10, 11]);
    expect(c.read(blockReasonsProvider)['n2'], {
      6: BlockReason.beforeRadiationLeave,
      7: BlockReason.beforeRadiationLeave,
      8: BlockReason.radiationLeave,
      9: BlockReason.radiationLeave,
      10: BlockReason.afterRadiationLeave,
      11: BlockReason.afterRadiationLeave,
    });
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
    final c = container();
    final blocked = c.read(effectiveBlockedDaysProvider);
    // 1 istenmeyen, 8 izin öncesi iş günü, 9 izin, 10-11 izin sonrası.
    expect(blocked['n1'], [1, 8, 9, 10, 11]);
    expect(c.read(blockReasonsProvider)['n1'], {
      1: BlockReason.unavailable,
      8: BlockReason.beforeAnnualLeave,
      9: BlockReason.annualLeave,
      10: BlockReason.afterAnnualLeave,
      11: BlockReason.afterAnnualLeave,
    });
  });

  test('sonraki ayın yıllık izni bu ayın son günlerini kapatır', () {
    // n1 yıllık izni 2–6 Kasım (2 Kasım Pazartesi): Ekim'de 30–31 kapalı.
    boxes.monthPlans.put(
      '2026-11',
      const MonthPlan(
        year: 2026,
        month: 11,
        annualLeave: {
          'n1': [2, 3, 4, 5, 6],
        },
      ),
    );
    final blocked = container().read(effectiveBlockedDaysProvider);
    expect(blocked['n1'], [30, 31]);
  });

  test('önceki ayın yıllık izni bu ayın ilk günlerini kapatır', () {
    // n1 yıllık izni 26–30 Ekim (30 Ekim Cuma): Kasım'da 1 Pazar kapalı.
    boxes.monthPlans.put(
      '2026-10',
      const MonthPlan(
        year: 2026,
        month: 10,
        annualLeave: {
          'n1': [26, 27, 28, 29, 30],
        },
      ),
    );
    final blocked = computeEffectiveBlockedDays(
      const MonthPlan(year: 2026, month: 11),
      boxes.holidays.values,
      repository: MonthPlanRepository(boxes.monthPlans),
    );
    expect(blocked['n1'], [1]);
  });

  test('ay içinde pasife geçenin pasif günleri kapanır', () async {
    await boxes.people.put(
      'n1',
      Person(
        id: 'n1',
        name: 'Ayşe',
        role: Role.nurse,
        isActive: false,
        inactiveFrom: DateTime(2026, 10, 20),
      ),
    );
    final blocked = container().read(effectiveBlockedDaysProvider);
    expect(blocked['n1'], [for (var d = 20; d <= 31; d++) d]);
  });
}
