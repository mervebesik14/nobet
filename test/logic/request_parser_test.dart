import 'package:flutter_test/flutter_test.dart';
import 'package:nobet_listesi/logic/request_parser.dart';
import 'package:nobet_listesi/models/models.dart';

void main() {
  const people = [
    Person(id: 'e', name: 'Emre Dinç', role: Role.nurse),
    Person(id: 'f', name: 'Fatih Işık', role: Role.nurse),
    Person(id: 'n', name: 'Nur Karadaş', role: Role.nurse),
    Person(id: 'n2', name: 'Nur Yılmaz', role: Role.nurse),
    Person(id: 'a', name: 'Anıl Demirtaş', role: Role.radiologyTech),
  ];

  RequestParseResult parse(String text) =>
      RequestParser.parse(text: text, people: people, year: 2026, month: 12);

  test('compactDays: art arda üç ve fazlası aralık', () {
    expect(
      RequestParser.compactDays([7, 3, 12, 13, 14, 20, 21]),
      '3, 7, 12–14, 20, 21',
    );
    expect(RequestParser.compactDays([]), '');
  });

  test('mesaj şablonu ayın adını ve örnekleri içerir', () {
    final m = RequestParser.message(year: 2026, month: 12);
    expect(m, contains('Aralık 2026'));
    expect(m, contains('izin 20-24'));
  });

  test('WhatsApp iPhone ve Android biçimi, gün ve aralık', () {
    final r = parse(
      '[12.11.2026 14:03:12] Emre Dinç: 3, 7, 12-14 olmaz\n'
      '12.11.2026 14:05 - Fatih Işık: 5 ve 6 tutamam\n',
    );
    expect(r.requests['e']!.unavailable, {3, 7, 12, 13, 14});
    expect(r.requests['f']!.unavailable, {5, 6});
    expect(r.unmatched, isEmpty);
  });

  test('izin, şua, rapor ve sonradan gelen "olmaz"', () {
    final r = parse('Emre Dinç: izin 20-22, 3 5 olmaz\nAnıl: şua 1-2; rapor 9');
    final e = r.requests['e']!;
    expect(e.leaves[LeaveType.annual], {20, 21, 22});
    expect(e.unavailable, {3, 5});
    final a = r.requests['a']!;
    expect(a.leaves[LeaveType.radiation], {1, 2});
    expect(a.leaves[LeaveType.sick], {9});
    expect(a.unavailable, isEmpty);
  });

  test('ad tekse yalnız ilk ad; aynı ilk ad iki kişideyse tam ad gerekir', () {
    final r = parse('Fatih: 4\nNur: 8\nNur Yılmaz: 9');
    expect(r.requests['f']!.unavailable, {4});
    expect(r.requests['n2']!.unavailable, {9});
    expect(r.requests.containsKey('n'), isFalse);
    expect(r.unmatched, ['Nur: 8']);
  });

  test(
    'devam satırı önceki mesaja eklenir; aynı kişinin mesajları birleşir',
    () {
      final r = parse(
        '[12.11.2026 14:03] Emre Dinç: 3 olmaz\n'
        'bir de 10\n'
        '[12.11.2026 15:00] Emre Dinç: izin 28-29',
      );
      final e = r.requests['e']!;
      expect(e.unavailable, {3, 10});
      expect(e.leaves[LeaveType.annual], {28, 29});
    },
  );

  test('saat, başka ayın tarihi, süre ve fazla mesai gün sayılmaz', () {
    final r = parse(
      'Emre Dinç: 30 Kasım ve 2 Aralık olmaz, 14:30 da yazıyorum, 3 gün '
      'yoğunum, 15.12 olmaz, 1.11 de olmaz. Fazla mesai istiyorum',
    );
    final e = r.requests['e']!;
    expect(e.unavailable, {2, 15});
    expect(e.overtime, isTrue);
  });

  test('"yok" diyen yanıtlamış sayılır ama isteği yoktur; 32 atlanır', () {
    final r = parse('Fatih Işık: yok\nEmre Dinç: 32, 4');
    expect(r.replied, {'f', 'e'});
    expect(r.requests.containsKey('f'), isFalse);
    expect(r.requests['e']!.unavailable, {4});
    expect(r.warnings.single, contains('32'));
  });

  test('fazla mesai istemiyorum', () {
    final r = parse('Emre Dinç: fazla mesai istemiyorum, 6');
    expect(r.requests['e']!.overtime, isFalse);
    expect(r.requests['e']!.unavailable, {6});
  });

  test('"10\'dan 12\'ye" ve "10 ile 12 arası" aralıktır', () {
    final r = parse("Emre Dinç: 10'dan 12'ye\nFatih Işık: 20 ile 22 arası");
    expect(r.requests['e']!.unavailable, {10, 11, 12});
    expect(r.requests['f']!.unavailable, {20, 21, 22});
  });

  test('tercih edilen günler', () {
    const people = [Person(id: 'a', name: 'Ayşe', role: Role.nurse)];
    PersonRequest r(String body) => RequestParser.parse(
      text: 'Ayşe: $body',
      people: people,
      year: 2026,
      month: 12,
    ).requests['a']!;
    expect(r('12, 15 istiyorum').preferred, {12, 15});
    expect(r('tercih 3, 5. 8 olmaz').preferred, {3, 5});
    expect(r('tercih 3, 5. 8 olmaz').unavailable, {8});
    // "izin istiyorum 20-22" izin kalır.
    final leave = r('izin istiyorum 20-22');
    expect(leave.preferred, isEmpty);
    expect(leave.leaves[LeaveType.annual], {20, 21, 22});
  });
}
