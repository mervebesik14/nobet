import 'package:flutter_test/flutter_test.dart';
import 'package:nobet_listesi/logic/block_reason.dart';

void main() {
  test('aynı güne düşen nedenlerden öncelikli olan kalır', () {
    final reasons = BlockReason.combine({
      BlockReason.unavailable: {
        'a': [1, 2],
        'b': [5],
      },
      BlockReason.annualLeave: {
        'a': [2, 3],
      },
      BlockReason.beforeAnnualLeave: {
        'a': [1, 4],
      },
      BlockReason.inactive: {'c': <int>[]},
    });
    expect(reasons['a'], {
      1: BlockReason.unavailable, // istemediği gün izin öncesinden önce
      2: BlockReason.annualLeave, // izin istemediği günden önce
      3: BlockReason.annualLeave,
      4: BlockReason.beforeAnnualLeave,
    });
    expect(reasons['b'], {5: BlockReason.unavailable});
    expect(reasons.containsKey('c'), isFalse);
    expect(BlockReason.days(reasons), {
      'a': [1, 2, 3, 4],
      'b': [5],
    });
  });

  test('mesajlar nedeni söyler', () {
    expect(
      BlockReason.unavailable.message('Fatih', '16 Ekim'),
      'Fatih istemediği güne (16 Ekim) atandı.',
    );
    expect(
      BlockReason.inactive.message('Fatih', '16 Ekim'),
      'Fatih pasif olduğu güne (16 Ekim) atandı.',
    );
    expect(
      BlockReason.afterAnnualLeave.message('Fatih', '17 Ekim'),
      contains('ilk iş gününde'),
    );
  });

  test('şua izni dönüşü mesajı', () {
    expect(
      BlockReason.afterRadiationLeave.message('Ali', '10 Ekim'),
      'Ali şua izni dönüşü ilk iş gününden önceki güne (10 Ekim) atandı. '
      'Şua izninden sonra ilk nöbet ilk iş gününde olabilir.',
    );
  });
}
