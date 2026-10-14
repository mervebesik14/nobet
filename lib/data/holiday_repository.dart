import 'package:hive_ce/hive_ce.dart';

import '../models/models.dart';
import 'turkish_holidays.dart';

/// Tatilleri saklar; anahtar `yyyy-MM-dd`, yani bir güne tek tatil düşer.
class HolidayRepository {
  HolidayRepository(this._box, this._meta);

  static const _seededYearsKey = 'seededHolidayYears';
  static const _religiousTaggedKey = 'religiousHolidaysTagged';

  final Box<Holiday> _box;
  final Box<dynamic> _meta;

  /// Tüm tatiller, tarihe göre sıralı.
  List<Holiday> getAll() =>
      _box.values.toList()..sort((a, b) => a.date.compareTo(b.date));

  List<Holiday> getForMonth(int year, int month) => getAll()
      .where((h) => h.date.year == year && h.date.month == month)
      .toList();

  Holiday? getByDate(DateTime date) => _box.get(Holiday.keyFor(date));

  bool get isEmpty => _box.isEmpty;

  /// Aynı güne kayıtlı tatil varsa üzerine yazar.
  Future<void> save(Holiday holiday) => _box.put(holiday.key, holiday);

  Future<void> saveAll(Iterable<Holiday> holidays) =>
      _box.putAll({for (final h in holidays) h.key: h});

  Future<void> delete(DateTime date) => _box.delete(Holiday.keyFor(date));

  /// Hazır Türkiye tatilleri yüklenmiş yıllar.
  Set<int> get seededYears => {
    ...(_meta.get(_seededYearsKey) as List? ?? const []).cast<int>(),
  };

  /// [year] yılının hazır tatillerini ilk seferde yükler, sonra dokunmaz:
  /// kullanıcının sildiği ya da düzenlediği tatiller geri gelmez. Aynı güne
  /// kullanıcının eklediği bir tatil varsa o korunur. Yükleme yapıldıysa true.
  Future<bool> ensureYearSeeded(int year) async {
    final seeded = seededYears;
    if (seeded.contains(year)) return false;
    await _box.putAll({
      for (final h in TurkishHolidays.forYear(year))
        if (!_box.containsKey(h.key)) h.key: h,
    });
    await _meta.put(_seededYearsKey, (seeded..add(year)).toList()..sort());
    return true;
  }

  /// Dini bayram alanı eklenmeden önce kaydedilmiş Ramazan / Kurban Bayramı
  /// günlerini bir kez dini bayram olarak işaretler.
  Future<void> tagReligiousHolidays() async {
    if (_meta.get(_religiousTaggedKey) == true) return;
    await _box.putAll({
      for (final h in _box.values)
        if (!h.isReligious && Holiday.isReligiousName(h.name))
          h.key: h.copyWith(isReligious: true),
    });
    await _meta.put(_religiousTaggedKey, true);
  }

  Stream<BoxEvent> watch() => _box.watch();
}
