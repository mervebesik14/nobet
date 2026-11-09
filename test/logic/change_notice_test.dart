import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:nobet_listesi/logic/change_notice.dart';
import 'package:nobet_listesi/models/models.dart';

void main() {
  setUpAll(() => initializeDateFormatting('tr_TR'));

  const people = [
    Person(id: 'a', name: 'Ayşe', role: Role.nurse),
    Person(id: 'b', name: 'Banu', role: Role.nurse),
    Person(id: 'c', name: 'Cemile', role: Role.nurse),
  ];

  test('kişi bazlı fark ve mesaj', () {
    final changes = ChangeNotice.compute(
      before: const {
        12: DayAssignment(day: 12, nurseIds: ['a', 'c']),
        15: DayAssignment(day: 15, nurseIds: ['b', 'c']),
      },
      after: const {
        12: DayAssignment(day: 12, nurseIds: ['b', 'c'], shift16aIds: ['c']),
        15: DayAssignment(day: 15, nurseIds: ['a', 'c']),
      },
      people: people,
    );
    expect([for (final c in changes) c.person.id], ['a', 'b', 'c']);
    expect(
      ChangeNotice.message(changes.first, 2026, 10),
      'Merhaba Ayşe, Ekim nöbet listesinde senin için değişiklik var:\n'
      '• 12 Ekim Pazartesi: 24 kaldırıldı\n'
      '• 15 Ekim Perşembe: 24 yazıldı',
    );
    expect(ChangeNotice.lines(changes.last, 2026, 10), [
      '12 Ekim Pazartesi: 24 → 16A',
    ]);
  });

  test('değişiklik yoksa boş', () {
    const a = {
      12: DayAssignment(day: 12, nurseIds: ['a']),
    };
    expect(ChangeNotice.compute(before: a, after: a, people: people), isEmpty);
  });
}
