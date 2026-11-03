import 'package:flutter_test/flutter_test.dart';
import 'package:nobet_listesi/logic/custom_shift_rules.dart';
import 'package:nobet_listesi/models/models.dart';

void main() {
  const existing = [CustomShift(code: '19A', startMinute: 780, hours: 19)];

  test('geçerli tanım', () {
    expect(
      CustomShiftRules.error(code: '12g', hours: 12, existing: existing),
      isNull,
    );
    expect(CustomShift.normalize(' 12 g '), '12G');
    expect(CustomShiftRules.parseHours('7,5'), 7.5);
    expect(CustomShiftRules.parseHours('x'), isNull);
  });

  test('hatalar', () {
    String? e(String code, double? hours) =>
        CustomShiftRules.error(code: code, hours: hours, existing: existing);
    expect(e('', 5), contains('adı'));
    expect(e('ABCDE', 5), contains('en fazla'));
    expect(e('16a', 5), contains('hazır'));
    expect(e('12', 5), contains('hazır'));
    expect(e('19a', 5), contains('zaten'));
    expect(e('X', null), contains('Süreyi'));
    expect(e('X', 30), contains('arasında'));
  });

  test('tanım: açıklama ve JSON', () {
    const s = CustomShift(code: '19A', startMinute: 780, hours: 19);
    expect(s.description, '13:00 · 19 sa · nöbet koltuğu');
    expect(
      const CustomShift(code: 'G', hours: 7.5, fillsSeat: false).description,
      '08:00 · 7,5 sa · ek mesai',
    );
    expect(CustomShift.fromJson(s.toJson()), s);
    const settings = RosterSettings(customShifts: [s]);
    expect(RosterSettings.fromJson(settings.toJson()), settings);
    expect(settings.customShift('19A'), s);
    expect(settings.customShift('X'), isNull);
  });
}
