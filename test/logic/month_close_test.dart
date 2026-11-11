import 'package:flutter_test/flutter_test.dart';
import 'package:nobet_listesi/logic/month_close.dart';

void main() {
  test('sıradaki adım ve saklama', () {
    expect(MonthClose.next({}), CloseStep.check);
    expect(
      MonthClose.next({CloseStep.check, CloseStep.lock}),
      CloseStep.publish,
    );
    expect(MonthClose.next({...CloseStep.values}), isNull);
    expect(MonthClose.key(2026, 11), 'monthClose/2026-11');
    expect(MonthClose.fromNames(['lock', 'x', 'backup']), {
      CloseStep.lock,
      CloseStep.backup,
    });
  });

  test('kontrol satırları', () {
    expect(
      MonthClose.checkLines(
        missingSeats: 0,
        violations: 0,
        overCapNames: const [],
        payHourCap: 130,
      ),
      ['Her şey yolunda.'],
    );
    expect(
      MonthClose.checkLines(
        missingSeats: 2,
        violations: 1,
        overCapNames: const ['Ayşe'],
        payHourCap: 130,
      ),
      [
        '2 koltuk boş.',
        '1 kural uyarısı var.',
        'Ücretli 130 saat sınırını aşanlar: Ayşe.',
      ],
    );
  });
}
