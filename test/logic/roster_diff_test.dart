import 'package:flutter_test/flutter_test.dart';
import 'package:nobet_listesi/logic/roster_diff.dart';
import 'package:nobet_listesi/models/models.dart';

void main() {
  const names = {'a': 'Ayşe', 'b': 'Banu', 'h': 'Hale', 'm': 'Mehmet'};
  String name(String id) => names[id] ?? 'Silinmiş kişi';

  test('yerine yazma, çıkarma, ekleme ve takas', () {
    final lines = RosterDiff.describe(
      month: 10,
      before: const {
        3: DayAssignment(day: 3, nurseIds: ['a', 'b'], techId: 'm'),
        4: DayAssignment(day: 4, nurseIds: ['a', 'b'], techId: 'm'),
        5: DayAssignment(day: 5, nurseIds: ['a'], techId: 'm'),
      },
      after: const {
        3: DayAssignment(day: 3, nurseIds: ['h', 'b'], techId: 'm'),
        4: DayAssignment(day: 4, nurseIds: ['a'], techId: 'm'),
        5: DayAssignment(day: 5, nurseIds: ['a', 'h'], techId: 'm'),
      },
      name: name,
    );
    expect(lines, [
      '3 Ekim: Ayşe yerine Hale',
      '4 Ekim: Banu çıkarıldı',
      '5 Ekim: Hale eklendi',
    ]);
  });

  test('7A elle seçimleri', () {
    final lines = RosterDiff.describe(
      month: 10,
      before: const {},
      after: const {},
      overridesBefore: const {9: 'a', 12: 'b'},
      overridesAfter: const {9: 'h', 14: 'a'},
      name: name,
    );
    expect(lines, [
      '7A 9 Ekim: Ayşe yerine Hale',
      '7A 12 Ekim: Banu yerine otomatik seçim',
      '7A 14 Ekim: Ayşe yazıldı',
    ]);
  });

  test('değişiklik yoksa boş', () {
    const a = {
      3: DayAssignment(day: 3, nurseIds: ['a', 'b']),
    };
    expect(
      RosterDiff.describe(month: 10, before: a, after: a, name: name),
      isEmpty,
    );
  });

  test('teknikerin elle 7A günleri', () {
    expect(
      RosterDiff.describe(
        month: 10,
        before: const {},
        after: const {},
        techDayShiftsBefore: const {
          't': [5, 9],
        },
        techDayShiftsAfter: const {
          't': [9, 12],
        },
        name: (id) => 'Ali',
      ),
      ['7A 5 Ekim: Ali kaldırıldı', '7A 12 Ekim: Ali yazıldı'],
    );
  });
}
