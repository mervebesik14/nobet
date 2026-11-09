import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:nobet_listesi/logic/text_edits.dart';
import 'package:nobet_listesi/models/models.dart';

void main() {
  setUpAll(() => initializeDateFormatting('tr_TR'));

  const people = [
    Person(id: 'a', name: 'Ayşe Yılmaz', role: Role.nurse),
    Person(id: 'b', name: 'Banu', role: Role.nurse),
    Person(id: 'c', name: 'Cemile', role: Role.nurse),
    Person(id: 'n', name: 'Nur', role: Role.nurse),
    Person(id: 'y1', name: 'Yasin Kaya', role: Role.nurse),
    Person(id: 'y2', name: 'Yasin Demir', role: Role.nurse),
    Person(id: 't', name: 'Tarık', role: Role.radiologyTech),
  ];

  List<TextEditLine> parse(String text) => TextEdits.parse(
    text: text,
    people: people,
    daysInMonth: 30,
    codes: const ['4A', '19A'],
  );

  test('komutlar çözülür', () {
    final lines = parse(
      "Ayşe 12'yi Banu'yla değiştir\n"
      'Ayşe 12 Banu 15 takas; Nur 26ya 4A\n'
      'Cemile 3 5 7 yaz\n'
      'Cemile 3 24\n'
      'Ayşe 3 sil\n'
      "12'de Banu yerine Cemile\n"
      'Banuyla Cemile 4 değiştir',
    );
    final e = [for (final l in lines) l.edit!];
    expect(e[0].describe(11), '12 Kasım: Ayşe Yılmaz yerine Banu');
    expect(e[1].describe(11), 'Takas: Ayşe Yılmaz 12 Kasım ↔ Banu 15 Kasım');
    expect(e[2].describe(11), 'Nur: 26 Kasım → 4A');
    expect(e[3].describe(11), 'Cemile: 3 Kasım, 5 Kasım, 7 Kasım → 24');
    expect(e[4].describe(11), 'Cemile: 3 Kasım → 24');
    expect(e[5].describe(11), 'Ayşe Yılmaz: 3 Kasım nöbeti silinir');
    expect(e[6].describe(11), '12 Kasım: Banu yerine Cemile');
    expect(e[7].kind, TextEditKind.replace);
  });

  test('hatalar', () {
    expect(parse('Zeynep 3').single.error, 'Kişi adı bulunamadı.');
    expect(parse('Yasin 3').single.error, contains('birden çok kişiye'));
    expect(parse('Yasin Kaya 3').single.edit!.person.id, 'y1');
    expect(parse('Ayşe 31').single.error, '31. gün bu ayda yok.');
    expect(parse('Ayşe').single.error, contains('gün yazılmamış'));
  });

  test(
    'uygulama: değiştir, takas, yaz, sil, ek mesai; hata ötekini durdurmaz',
    () {
      final plan = MonthPlan(
        year: 2026,
        month: 11,
        assignments: {
          3: const DayAssignment(day: 3, nurseIds: ['a', 'c'], techId: 't'),
          12: const DayAssignment(day: 12, nurseIds: ['a', 'n'], techId: 't'),
          15: const DayAssignment(day: 15, nurseIds: ['b', 'c'], techId: 't'),
          26: const DayAssignment(day: 26, nurseIds: ['a', 'b']),
        },
      );
      const settings = RosterSettings(
        customShifts: [
          CustomShift(code: '4A', hours: 4, fillsSeat: false),
          CustomShift(code: '19A', startMinute: 780, hours: 19),
        ],
      );
      final edits = [
        for (final l in parse(
          'Ayşe 12 Banu 15 takas\n'
          "Nur 26'ya 4A\n"
          'Cemile 3 sil\n'
          'Nur 3 19A\n'
          'Cemile 26 24\n'
          'Tarık 9 7A',
        ))
          l.edit!,
      ];
      final r = TextEdits.apply(
        plan: plan,
        edits: edits,
        settings: settings,
        holidays: const [],
      );
      expect(r.assignments[12]!.nurseIds, ['b', 'n']);
      expect(r.assignments[15]!.nurseIds, ['a', 'c']);
      expect(r.assignments[26]!.extraShifts, {'n': '4A'});
      expect(r.assignments[3]!.nurseIds, ['a', 'n']);
      expect(r.assignments[3]!.shiftCode('n'), '19A');
      expect(r.techDayShifts, {
        't': [9],
      });
      // 26'da iki koltuk dolu → hata, ötekiler uygulandı.
      expect(r.errors.single, contains('hemşire koltukları dolu'));
      expect(r.done, hasLength(5));
    },
  );
}
