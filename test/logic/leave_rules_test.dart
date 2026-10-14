import 'package:flutter_test/flutter_test.dart';
import 'package:nobet_listesi/data/turkish_holidays.dart';
import 'package:nobet_listesi/logic/leave_rules.dart';

void main() {
  // Ekim 2026: 1 Per, 2 Cum, 3 Cmt, 4 Paz, 5 Pzt ... 9 Cum, 10 Cmt, 11 Paz,
  // 12 Pzt ... 28 Çar (arife, yarım gün), 29 Per (Cumhuriyet, tam tatil),
  // 30 Cum, 31 Cmt.
  final holidays = TurkishHolidays.forYear(2026);

  Set<int> blocked(List<int> leave) => LeaveRules.postAnnualLeaveBlockedDays(
    year: 2026,
    month: 10,
    annualLeaveDays: leave,
    holidays: holidays,
  );

  test('izin yoksa engel yok', () {
    expect(blocked([]), isEmpty);
  });

  test('Cuma biten izin: Cmt-Paz kapalı, ilk nöbet Pazartesi', () {
    // İzin 5–9 (9 Cuma). 10 Cmt ve 11 Paz nöbete kapalı; 12 Pzt serbest.
    expect(blocked([5, 6, 7, 8, 9]), {10, 11});
  });

  test('hafta içi biten izin: ertesi iş günü hemen serbest', () {
    // İzin 12–13 (13 Salı). 14 Çar iş günü → engel yok.
    expect(blocked([12, 13]), isEmpty);
  });

  test('izin bitişinden sonra tam tatil varsa o da kapalı', () {
    // İzin 27–28 (28 Çar, arife iş günü sayılır ve izinli). 29 Per Cumhuriyet
    // tam tatil → kapalı; 30 Cum iş günü → serbest.
    expect(blocked([27, 28]), {29});
  });

  test('tek günlük Cuma izni de hafta sonunu kapatır', () {
    expect(blocked([9]), {10, 11});
  });

  test('ayrı aralıkların her biri kendi hafta sonunu kapatır', () {
    // 2 Cum (bitiş) → 3,4 kapalı. 9 Cum (bitiş) → 10,11 kapalı.
    expect(blocked([1, 2, 8, 9]), {3, 4, 10, 11});
  });

  test('ayın son günü biten izinde sonraki aya taşan engel yok', () {
    // 31 Cmt izinli; 31 sonrası ay dışı.
    expect(blocked([31]), isEmpty);
  });

  test('izinli günlerin kendisi engel kümesine girmez', () {
    final out = blocked([9]);
    expect(out.contains(9), isFalse);
  });

  group('izin öncesi', () {
    Set<int> pre(List<int> leave) => LeaveRules.preAnnualLeaveBlockedDays(
      year: 2026,
      month: 10,
      annualLeaveDays: leave,
      holidays: holidays,
    );

    test(
      'Pazartesi başlayan izin: Cuma-Cmt-Paz kapalı, son nöbet Perşembe',
      () {
        // İzin 12–16 (12 Pzt). 9 Cum, 10 Cmt, 11 Paz kapalı; 8 Per serbest.
        expect(pre([12, 13, 14, 15, 16]), {9, 10, 11});
      },
    );

    test('hafta ortası başlayan izin: yalnız önceki iş günü kapalı', () {
      // İzin 14 (Çar). 13 Sal kapalı; 12 Pzt serbest.
      expect(pre([14]), {13});
    });

    test('araya tam gün tatil girerse o da atlanır', () {
      // İzin 30 (Cum). 29 Per Cumhuriyet tam tatil, 28 Çar arife (iş günü):
      // 28 ve 29 kapalı; son nöbet 27 Sal.
      expect(pre([30]), {28, 29});
    });

    test('ayın ilk günleri: ay dışına taşan engel yok', () {
      expect(pre([1]), isEmpty);
      // İzin 5 (Pzt): 2 Cum, 3 Cmt, 4 Paz kapalı; son nöbet 1 Per.
      expect(pre([5, 6]), {2, 3, 4});
    });
  });

  test('öncesi ve sonrası birlikte: 12–16 izni', () {
    final all = LeaveRules.annualLeaveBlockedDays(
      year: 2026,
      month: 10,
      annualLeaveDays: [12, 13, 14, 15, 16],
      holidays: holidays,
    );
    // Önce 9–11, sonra 17–18 (16 Cum biter, ilk nöbet 19 Pzt).
    expect(all, {9, 10, 11, 17, 18});
  });
}
