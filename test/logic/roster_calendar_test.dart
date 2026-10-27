import 'package:flutter_test/flutter_test.dart';
import 'package:nobet_listesi/logic/day_shift_planner.dart';
import 'package:nobet_listesi/logic/personal_roster.dart';
import 'package:nobet_listesi/logic/roster_calendar.dart';
import 'package:nobet_listesi/models/models.dart';

void main() {
  const people = [
    Person(id: 'a', name: 'Ayşe Işık', role: Role.nurse),
    Person(id: 'b', name: 'Banu', role: Role.nurse),
    Person(id: 't', name: 'Ali', role: Role.radiologyTech),
    Person(id: 'u', name: 'Veli', role: Role.radiologyTech),
  ];
  const plan = MonthPlan(
    year: 2026,
    month: 11,
    assignments: {
      // 30 Kasım: ertesi gün Aralık.
      30: DayAssignment(day: 30, nurseIds: ['a', 'b'], techId: 't'),
      4: DayAssignment(
        day: 4,
        nurseIds: ['b', 'a'],
        techId: 'u',
        tech16bId: 't',
      ),
    },
  );
  final now = DateTime.utc(2026, 10, 27, 15, 4, 5);

  List<String> unfold(String ics) =>
      ics.replaceAll('\r\n ', '').split('\r\n')..removeLast();

  test('24 nöbet: 08:00 → ertesi gün 08:00, ay sonunda ay değişir', () {
    final ics = RosterCalendar.ics(
      data: PersonalRoster.build(plan: plan, person: people[0], people: people),
      now: now,
    );
    final lines = unfold(ics);
    expect(lines.first, 'BEGIN:VCALENDAR');
    expect(lines.last, 'END:VCALENDAR');
    expect('BEGIN:VEVENT'.allMatches(ics).length, 2);
    expect(lines, contains('X-WR-CALNAME:Ayşe Işık nöbetleri'));
    expect(lines, contains('DTSTART:20261130T080000'));
    expect(lines, contains('DTEND:20261201T080000'));
    expect(lines, contains('DTSTART:20261104T080000'));
    expect(lines, contains('SUMMARY:Nöbet (24)'));
    expect(lines, contains('UID:nobetci-a-20261130-24@nobetci'));
    expect(lines, contains('DTSTAMP:20261027T150405Z'));
    // Virgüller ve satır sonu kaçışlı.
    expect(
      lines,
      contains(r'DESCRIPTION:Hemşire: Ayşe Işık\, Banu\nRadyoloji: Ali'),
    );
    // Önceki akşam 20:00 hatırlatma.
    expect(lines.where((l) => l == 'TRIGGER:-PT12H'), hasLength(2));
    // Satır sonları CRLF, satırlar 75 baytı aşmaz.
    expect(ics.split('\r\n').every((l) => l.codeUnits.length <= 75), isTrue);
  });

  test('16B: 08:00 → 24:00; 7A: günün mesai saati kadar', () {
    final ics = RosterCalendar.ics(
      data: PersonalRoster.build(plan: plan, person: people[2], people: people),
      dayShifts: const [
        DayShift(day: 9, personId: 't', hours: 7, isSubstitute: false),
        DayShift(day: 10, personId: 't', hours: 5, isSubstitute: false),
        DayShift(day: 11, personId: 'a', hours: 7, isSubstitute: false),
      ],
      now: now,
    );
    final lines = unfold(ics);
    expect(lines, contains('SUMMARY:Nöbet (16B)'));
    expect(lines, contains('DTSTART:20261104T080000'));
    expect(lines, contains('DTEND:20261105T000000'));
    expect(lines, contains('SUMMARY:7A (gündüz mesaisi)'));
    expect(lines, contains('DTEND:20261109T150000'));
    expect(lines, contains('DTEND:20261110T130000'));
    // Başkasının 7A'sı girmez.
    expect(lines, isNot(contains('DTSTART:20261111T080000')));
    expect('BEGIN:VEVENT'.allMatches(ics).length, 4);
  });

  test('uzun satırlar 75 baytta katlanır, Türkçe harfler bölünmez', () {
    final long = [
      for (var i = 0; i < 6; i++)
        Person(id: 'n$i', name: 'Şükrü Öztürkoğlu $i', role: Role.nurse),
    ];
    final ics = RosterCalendar.ics(
      data: PersonalRoster.build(
        plan: const MonthPlan(
          year: 2026,
          month: 11,
          assignments: {
            2: DayAssignment(
              day: 2,
              nurseIds: ['n0', 'n1', 'n2', 'n3', 'n4', 'n5'],
            ),
          },
        ),
        person: long.first,
        people: long,
      ),
      now: now,
    );
    for (final l in ics.split('\r\n')) {
      expect(l.length, lessThanOrEqualTo(75));
      expect(String.fromCharCodes(l.runes), l);
    }
    expect(
      unfold(ics).firstWhere((l) => l.startsWith('DESCRIPTION:H')),
      contains('Şükrü Öztürkoğlu 5'),
    );
  });
}
