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

  group('toggle (serbest düzenleme)', () {
    const base = {
      3: DayAssignment(day: 3, nurseIds: ['a', 'b'], techId: 't'),
    };

    test('dolu güne üçüncü hemşire eklenir, tekrar dokununca çıkar', () {
      final added = RosterEditor.toggle(
        base,
        day: 3,
        personId: 'c',
        role: Role.nurse,
      );
      expect(added[3]!.nurseIds, ['a', 'b', 'c']);
      final removed = RosterEditor.toggle(
        added,
        day: 3,
        personId: 'a',
        role: Role.nurse,
      );
      expect(removed[3]!.nurseIds, ['b', 'c']);
      // Kayıt olmayan güne de eklenir.
      expect(
        RosterEditor.toggle(
          base,
          day: 9,
          personId: 'a',
          role: Role.nurse,
        )[9]!.nurseIds,
        ['a'],
      );
    });

    test('tekniker: boş 24, sonra 16B; ikisi doluysa hata; çıkarma', () {
      final second = RosterEditor.toggle(
        base,
        day: 3,
        personId: 'u',
        role: Role.radiologyTech,
        twoTechs: true,
      );
      expect(second[3]!.tech16bId, 'u');
      expect(
        () => RosterEditor.toggle(
          second,
          day: 3,
          personId: 'v',
          role: Role.radiologyTech,
          twoTechs: true,
        ),
        throwsA(isA<RosterEditException>()),
      );
      expect(
        () => RosterEditor.toggle(
          base,
          day: 3,
          personId: 'v',
          role: Role.radiologyTech,
        ),
        throwsA(isA<RosterEditException>()),
      );
      final removed = RosterEditor.toggle(
        second,
        day: 3,
        personId: 't',
        role: Role.radiologyTech,
      );
      expect(removed[3]!.techId, isNull);
      expect(removed[3]!.tech16bId, 'u');
    });
  });

  group('setTechSeat (16B / 24)', () {
    const day = DayAssignment(day: 5, nurseIds: ['n1', 'n2'], techId: 't1');
    final base = {5: day};

    test('boş 16B koltuğuna yazar, 24 yerinde kalır', () {
      final r = RosterEditor.setTechSeat(
        base,
        day: 5,
        personId: 't2',
        secondary: true,
      );
      expect(
        r[5],
        const DayAssignment(
          day: 5,
          nurseIds: ['n1', 'n2'],
          techId: 't1',
          tech16bId: 't2',
        ),
      );
      expect(base[5], day, reason: 'girdi değişmez');
    });

    test("24 tutan 16B'ye geçer; 24 boş kalır", () {
      final r = RosterEditor.setTechSeat(
        base,
        day: 5,
        personId: 't1',
        secondary: true,
      );
      expect(r[5]!.techId, isNull);
      expect(r[5]!.tech16bId, 't1');
    });

    test("16B tutan 24'e geçer; koltuktaki kişinin yerine", () {
      final r = RosterEditor.setTechSeat(
        {5: const DayAssignment(day: 5, techId: 't1', tech16bId: 't2')},
        day: 5,
        personId: 't2',
        secondary: false,
      );
      expect(r[5]!.techId, 't2');
      expect(r[5]!.tech16bId, isNull);
    });

    test('listede olmayan güne de yazar', () {
      final r = RosterEditor.setTechSeat(
        const {},
        day: 9,
        personId: 't3',
        secondary: true,
      );
      expect(r[9], const DayAssignment(day: 9, tech16bId: 't3'));
    });
  });
}
