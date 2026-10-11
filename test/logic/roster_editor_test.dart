import 'package:flutter_test/flutter_test.dart';
import 'package:nobet_listesi/logic/roster_editor.dart';
import 'package:nobet_listesi/models/models.dart';

void main() {
  final base = {
    1: const DayAssignment(day: 1, nurseIds: ['a', 'b'], techId: 'm'),
    2: const DayAssignment(day: 2, nurseIds: ['c', 'd'], techId: 'z'),
    3: const DayAssignment(day: 3, nurseIds: ['a']),
  };

  group('replace', () {
    test('hemşire yerine başkası, sıra korunur; girdi değişmez', () {
      final r = RosterEditor.replace(
        base,
        day: 1,
        role: Role.nurse,
        oldId: 'a',
        newId: 'c',
        nursesPerDay: 2,
      );
      expect(r[1]!.nurseIds, ['c', 'b']);
      expect(base[1]!.nurseIds, ['a', 'b']);
    });

    test('nöbeti kaldırma ve boş koltuğa ekleme', () {
      final removed = RosterEditor.replace(
        base,
        day: 1,
        role: Role.radiologyTech,
        oldId: 'm',
        nursesPerDay: 2,
      );
      expect(removed[1]!.techId, isNull);

      final added = RosterEditor.replace(
        base,
        day: 3,
        role: Role.nurse,
        newId: 'b',
        nursesPerDay: 2,
      );
      expect(added[3]!.nurseIds, ['a', 'b']);

      final tech = RosterEditor.replace(
        base,
        day: 3,
        role: Role.radiologyTech,
        newId: 'z',
        nursesPerDay: 2,
      );
      expect(tech[3]!.techId, 'z');

      final newDay = RosterEditor.replace(
        base,
        day: 9,
        role: Role.nurse,
        newId: 'a',
        nursesPerDay: 2,
      );
      expect(newDay[9]!.nurseIds, ['a']);
    });

    test('yapısal hatalar reddedilir', () {
      expect(
        () => RosterEditor.replace(
          base,
          day: 1,
          role: Role.nurse,
          oldId: 'a',
          newId: 'b',
          nursesPerDay: 2,
        ),
        throwsA(isA<RosterEditException>()),
      );
      expect(
        () => RosterEditor.replace(
          base,
          day: 1,
          role: Role.nurse,
          newId: 'c',
          nursesPerDay: 2,
        ),
        throwsA(isA<RosterEditException>()),
      );
      expect(
        () => RosterEditor.replace(
          base,
          day: 1,
          role: Role.radiologyTech,
          oldId: 'z',
          newId: 'x',
          nursesPerDay: 2,
        ),
        throwsA(isA<RosterEditException>()),
      );
    });
  });

  group('swap', () {
    test('iki nöbet takas edilir', () {
      final r = RosterEditor.swap(
        base,
        a: 'a',
        dayA: 1,
        b: 'd',
        dayB: 2,
        role: Role.nurse,
        nursesPerDay: 2,
      );
      expect(r[1]!.nurseIds, ['d', 'b']);
      expect(r[2]!.nurseIds, ['c', 'a']);

      final t = RosterEditor.swap(
        base,
        a: 'm',
        dayA: 1,
        b: 'z',
        dayB: 2,
        role: Role.radiologyTech,
        nursesPerDay: 2,
      );
      expect(t[1]!.techId, 'z');
      expect(t[2]!.techId, 'm');
    });

    test('kişi diğer gün zaten nöbetçiyse takas yok', () {
      expect(
        () => RosterEditor.swap(
          base,
          a: 'b',
          dayA: 1,
          b: 'a',
          dayB: 3,
          role: Role.nurse,
          nursesPerDay: 2,
        ),
        throwsA(
          isA<RosterEditException>().having(
            (e) => e.message,
            'message',
            'İkinci kişi ilk gün zaten nöbetçi.',
          ),
        ),
      );
      expect(
        () => RosterEditor.swap(
          base,
          a: 'a',
          dayA: 1,
          b: 'a',
          dayB: 3,
          role: Role.nurse,
          nursesPerDay: 2,
        ),
        throwsA(isA<RosterEditException>()),
      );
    });
  });
}
