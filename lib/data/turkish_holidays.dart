import '../models/holiday.dart';

/// Türkiye resmi tatilleri.
///
/// Sabit tarihli tatiller her yıl için üretilir. Dini bayramlar hicri takvime
/// göre her yıl kaydığı için [_religious] tablosunda yıl yıl tutulur; tabloda
/// olmayan yıllar için bayramlar Tatiller ekranından elle eklenmelidir.
class TurkishHolidays {
  TurkishHolidays._();

  /// Ramazan ve Kurban Bayramı'nın ilk günleri (arife bir gün öncesidir).
  static final Map<int, ({DateTime ramazan, DateTime kurban})> _religious = {
    // Diyanet takvimi: Ramazan 20-22 Mart (arife 19 Mart),
    // Kurban 27-30 Mayıs (arife 26 Mayıs).
    2026: (ramazan: DateTime(2026, 3, 20), kurban: DateTime(2026, 5, 27)),
    // Diyanet 2027 takvimi: Ramazan 9-11 Mart (arife 8 Mart),
    // Kurban 16-19 Mayıs (arife 15 Mayıs). Doğrulanmalı.
    2027: (ramazan: DateTime(2027, 3, 9), kurban: DateTime(2027, 5, 16)),
    // Diyanet 2028 takvimini henüz yayımlamadı; astronomik hesaba göre
    // tahmin: Ramazan 26-28 Şubat (arife 25 Şubat), Kurban 4-7 Mayıs
    // (arife 3 Mayıs). Doğrulanmalı.
    2028: (ramazan: DateTime(2028, 2, 26), kurban: DateTime(2028, 5, 4)),
  };

  static const _fixed = <(int month, int day, String name, bool halfDay)>[
    (1, 1, 'Yılbaşı', false),
    (4, 23, 'Ulusal Egemenlik ve Çocuk Bayramı', false),
    (5, 1, 'Emek ve Dayanışma Günü', false),
    (5, 19, 'Atatürk\'ü Anma, Gençlik ve Spor Bayramı', false),
    (7, 15, 'Demokrasi ve Millî Birlik Günü', false),
    (8, 30, 'Zafer Bayramı', false),
    (10, 28, 'Cumhuriyet Bayramı Arifesi', true),
    (10, 29, 'Cumhuriyet Bayramı', false),
  ];

  /// Dini bayram tarihleri tabloda tanımlı yıllar.
  static Iterable<int> get religiousYears => _religious.keys;

  /// [year] için dini bayram tarihleri tanımlı mı?
  static bool hasReligiousHolidays(int year) => _religious.containsKey(year);

  /// [year] yılının tüm hazır tatilleri, tarihe göre sıralı ve
  /// `isPredefined = true`. Aynı güne iki tatil düşerse (ör. 2027'de Kurban
  /// Bayramı ile 19 Mayıs) tek kayıtta birleşir; biri tam günse gün tam
  /// tatildir.
  static List<Holiday> forYear(int year) {
    final byKey = <String, Holiday>{};
    void add(DateTime date, String name, {bool halfDay = false}) {
      final holiday = Holiday(
        date: date,
        name: name,
        isHalfDay: halfDay,
        isPredefined: true,
      );
      final existing = byKey[holiday.key];
      byKey[holiday.key] = existing == null
          ? holiday
          : existing.copyWith(
              name: '${existing.name} / $name',
              isHalfDay: existing.isHalfDay && halfDay,
            );
    }

    for (final (month, day, name, halfDay) in _fixed) {
      add(DateTime(year, month, day), name, halfDay: halfDay);
    }

    final religious = _religious[year];
    if (religious != null) {
      _addFeast(add, religious.ramazan, 'Ramazan Bayramı', 3);
      _addFeast(add, religious.kurban, 'Kurban Bayramı', 4);
    }

    return byKey.values.toList()..sort((a, b) => a.date.compareTo(b.date));
  }

  static void _addFeast(
    void Function(DateTime, String, {bool halfDay}) add,
    DateTime firstDay,
    String name,
    int days,
  ) {
    add(_addDays(firstDay, -1), '$name Arifesi', halfDay: true);
    for (var i = 0; i < days; i++) {
      add(_addDays(firstDay, i), '$name ${i + 1}. Gün');
    }
  }

  /// Yaz saati geçişlerinden etkilenmeden gün ekler.
  static DateTime _addDays(DateTime date, int days) =>
      DateTime(date.year, date.month, date.day + days);
}
