import 'package:flutter_test/flutter_test.dart';
import 'package:nobet_listesi/logic/past_roster_entry.dart';
import 'package:nobet_listesi/models/models.dart';

void main() {
  test('kişinin günleri yazılır, diğerlerine dokunulmaz', () {
    const before = {
      1: DayAssignment(day: 1, nurseIds: ['a', 'b']),
      2: DayAssignment(day: 2, nurseIds: ['a']),
      3: DayAssignment(day: 3, nurseIds: ['c'], techId: 't'),
    };
    final after = PastRosterEntry.setNurseDays(
      before,
      personId: 'a',
      days: {3, 5},
      daysInMonth: 30,
    );
    expect(after[1]!.nurseIds, ['b']);
    expect(after.containsKey(2), isFalse); // boş kalan gün silinir
    expect(after[3]!.nurseIds, ['c', 'a']);
    expect(after[3]!.techId, 't');
    expect(after[5]!.nurseIds, ['a']);
    expect(PastRosterEntry.nurseDaysOf(after, 'a'), {3, 5});
    expect(PastRosterEntry.nurseCounts(after), {1: 1, 3: 2, 5: 1});
  });

  test('koltuk sınırı yok: geçmiş kayıt olduğu gibi', () {
    final after = PastRosterEntry.setNurseDays(
      const {
        4: DayAssignment(day: 4, nurseIds: ['b', 'c']),
      },
      personId: 'a',
      days: {4},
      daysInMonth: 30,
    );
    expect(after[4]!.nurseIds, ['b', 'c', 'a']);
  });
}
