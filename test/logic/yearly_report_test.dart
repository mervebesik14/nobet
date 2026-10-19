import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nobet_listesi/logic/yearly_excel.dart';
import 'package:nobet_listesi/logic/yearly_report.dart';
import 'package:nobet_listesi/logic/yearly_summary.dart';
import 'package:nobet_listesi/models/models.dart';

void main() {
  group('YearlyReport.tint', () {
    test('ortalamaya yakınsa ya da kayıt yoksa renksiz', () {
      expect(YearlyReport.tint(null), isNull);
      expect(YearlyReport.tint(0.4), isNull);
      expect(YearlyReport.tint(-0.4), isNull);
    });

    test('üstü kırmızı, altı mavi; fark büyüdükçe koyulaşır', () {
      int r(int c) => c >> 16;
      int b(int c) => c & 0xFF;
      final above = YearlyReport.tint(1)!;
      final below = YearlyReport.tint(-1)!;
      expect(r(above), greaterThan(b(above)));
      expect(b(below), greaterThan(r(below)));
      // Daha büyük fark daha koyu (beyazdan uzak).
      final strong = YearlyReport.tint(3)!;
      expect(strong & 0xFF, lessThan(above & 0xFF));
      expect(YearlyReport.tint(5), strong, reason: 'en koyu sınırda kalır');
    });
  });

  group('YearlyExcel', () {
    final people = [
      for (var i = 1; i <= 4; i++)
        Person(id: 'n$i', name: 'Hemşire $i', role: Role.nurse),
    ];
    // Eylül: n1, n2 tek günler (15'er); n3, n4 çift günler (15'er).
    // Ekim: n1 3 nöbet, diğerleri 2'şer.
    final plans = [
      MonthPlan(
        year: 2026,
        month: 9,
        nurseOnly: true,
        assignments: {
          for (var d = 1; d <= 30; d++)
            d: DayAssignment(
              day: d,
              nurseIds: d.isOdd ? const ['n1', 'n2'] : const ['n3', 'n4'],
            ),
        },
      ),
      const MonthPlan(
        year: 2026,
        month: 10,
        nurseOnly: true,
        assignments: {
          1: DayAssignment(day: 1, nurseIds: ['n1', 'n2']),
          4: DayAssignment(day: 4, nurseIds: ['n1', 'n3']),
          7: DayAssignment(day: 7, nurseIds: ['n1', 'n4']),
          10: DayAssignment(day: 10, nurseIds: ['n2', 'n3']),
          13: DayAssignment(day: 13, nurseIds: ['n4']),
        },
      ),
    ];
    YearlySummary summary() => YearlySummary.build(
      year: 2026,
      plans: plans,
      people: people,
      holidays: const [],
      settings: const RosterSettings(),
    );

    test('iki sayfa: yıllık özet ve aylara göre', () {
      final files = {
        for (final f in ZipDecoder().decodeBytes(
          YearlyExcel.build(year: 2026, summary: summary()),
        ))
          f.name: utf8.decode(f.content),
      };
      expect(files['xl/workbook.xml'], contains('name="Yıllık Özet"'));
      expect(files['xl/workbook.xml'], contains('name="Aylara Göre"'));

      final totals = files['xl/worksheets/sheet1.xml']!;
      expect(totals, contains('2026 Yıllık Nöbet Özeti'));
      expect(totals, contains('Dahil aylar: Eylül, Ekim'));
      // n1: 15 + 3 = 18 nöbet, 18 × 24 = 432 saat.
      expect(totals, contains('<v>18</v>'));
      expect(totals, contains('<v>432</v>'));

      final byMonth = files['xl/worksheets/sheet2.xml']!;
      for (final m in YearlyReport.metrics) {
        expect(byMonth, contains('>${m.label}<'));
      }
      expect(byMonth, contains('>Eylül<'));
      expect(byMonth, contains('>Ekim<'));
      // Ekim'de n1 (3) ortalamanın (2) üstünde: kırmızı dolgu var.
      final red = YearlyReport.tint(
        1,
      )!.toRadixString(16).padLeft(6, '0').toUpperCase();
      expect(files['xl/styles.xml'], contains('FF$red'));
    });

    // Elle denetim için: XLSX_OUT=yol flutter test ... dosyayı yazar.
    test('isteğe bağlı: dosyayı diske yaz', () {
      final out = Platform.environment['XLSX_OUT'];
      if (out == null) return;
      File(
        out,
      ).writeAsBytesSync(YearlyExcel.build(year: 2026, summary: summary()));
    });
  });
}
