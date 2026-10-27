import 'package:flutter_test/flutter_test.dart';
import 'package:nobet_listesi/logic/turkish_collation.dart';

void main() {
  group('compareTurkish', () {
    test('Türkçe harfler kendi yerinde sıralanır', () {
      final names = [
        'Zeynep',
        'Çiğdem',
        'Ömer',
        'Cem',
        'Şule',
        'Selin',
        'Ümit',
        'Uğur',
        'Osman',
        'Derya',
      ];
      names.sort(compareTurkish);
      expect(names, [
        'Cem',
        'Çiğdem',
        'Derya',
        'Osman',
        'Ömer',
        'Selin',
        'Şule',
        'Uğur',
        'Ümit',
        'Zeynep',
      ]);
    });

    test('ı, i\'den önce gelir; I ve İ doğru küçültülür', () {
      final names = ['İlker', 'Işıl', 'ilknur', 'ırmak'];
      names.sort(compareTurkish);
      expect(names, ['ırmak', 'Işıl', 'İlker', 'ilknur']);
    });

    test('büyük/küçük harf duyarsız, kısa olan önce', () {
      expect(compareTurkish('ayşe', 'AYŞE KAYA'), lessThan(0));
      expect(compareTurkish('ali', 'Banu'), lessThan(0));
      expect(compareTurkish('Ali', 'Ali'), 0);
    });

    test('boşluk ve rakam harflerden önce', () {
      expect(compareTurkish('Ali Veli', 'Alican'), lessThan(0));
      expect(compareTurkish('Ali 2', 'Ali A'), lessThan(0));
    });
  });

  test('turkishUpperCase: i→İ, ı→I', () {
    expect(turkishUpperCase('Hemşireler'), 'HEMŞİRELER');
    expect(turkishUpperCase('ışık'), 'IŞIK');
  });

  test('normalizeName kırpar, boşlukları tekleştirir, Türkçe küçültür', () {
    expect(normalizeName('  AYŞE   IŞIK '), 'ayşe ışık');
    expect(normalizeName('İpek'), 'ipek');
  });
}
