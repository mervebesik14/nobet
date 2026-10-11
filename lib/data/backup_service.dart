import 'dart:convert';

import '../models/models.dart';
import 'hive_boxes.dart';

/// Geçersiz ya da bu uygulamaya ait olmayan yedek dosyası.
class BackupFormatException implements Exception {
  const BackupFormatException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Bir yedeğin içeriğinin özeti (geri yüklemeden önce onay için).
class BackupInfo {
  const BackupInfo({
    required this.exportedAt,
    required this.people,
    required this.holidays,
    required this.monthPlans,
  });

  final DateTime? exportedAt;
  final int people;
  final int holidays;
  final int monthPlans;
}

/// Tüm Hive verisini tek bir JSON belgesine yazar ve ondan geri yükler.
/// Veriler yalnızca telefonda durduğu için telefon değişince ya da uygulama
/// silinince tek güvence budur.
class BackupService {
  BackupService(this._boxes);

  static const format = 'nobet_listesi_yedek';
  static const version = 1;

  /// `app_meta` kutusundan yedeğe giren anahtarlar.
  static const _metaKeys = ['seededHolidayYears', 'themeMode'];

  final HiveBoxes _boxes;

  Map<String, dynamic> export({DateTime? now}) => {
    'format': format,
    'version': version,
    'exportedAt': (now ?? DateTime.now()).toIso8601String(),
    'people': [for (final p in _boxes.people.values) p.toJson()],
    'holidays': [for (final h in _boxes.holidays.values) h.toJson()],
    'monthPlans': [for (final m in _boxes.monthPlans.values) m.toJson()],
    'settings': (_boxes.settings.get('roster') ?? const RosterSettings())
        .toJson(),
    'meta': {
      for (final key in _metaKeys)
        if (_boxes.meta.get(key) != null) key: _boxes.meta.get(key),
    },
  };

  /// Okunaklı (girintili) JSON metni.
  String exportJson({DateTime? now}) =>
      const JsonEncoder.withIndent('  ').convert(export(now: now));

  /// Yedeği çözümler ve doğrular; veriye dokunmaz.
  static Map<String, dynamic> parse(String text) {
    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException {
      throw const BackupFormatException('Dosya geçerli bir JSON değil.');
    }
    if (decoded is! Map<String, dynamic> || decoded['format'] != format) {
      throw const BackupFormatException(
        'Bu dosya bir Nöbet Listesi yedeği değil.',
      );
    }
    final v = decoded['version'];
    if (v is! int || v > version) {
      throw const BackupFormatException(
        'Yedek, uygulamanın daha yeni bir sürümüyle alınmış.',
      );
    }
    return decoded;
  }

  static BackupInfo info(Map<String, dynamic> backup) {
    int count(String key) => (backup[key] as List? ?? const []).length;
    final at = backup['exportedAt'] as String?;
    return BackupInfo(
      exportedAt: at == null ? null : DateTime.tryParse(at),
      people: count('people'),
      holidays: count('holidays'),
      monthPlans: count('monthPlans'),
    );
  }

  /// Mevcut verinin tamamını silip yedekteki veriyi yazar. Önce her kayıt
  /// çözümlenir; bozuk bir kayıt varsa hiçbir şey silinmez.
  Future<void> restore(Map<String, dynamic> backup) async {
    List<Map<String, dynamic>> items(String key) => [
      for (final e in backup[key] as List? ?? const [])
        (e as Map).cast<String, dynamic>(),
    ];

    final List<Person> people;
    final List<Holiday> holidays;
    final List<MonthPlan> plans;
    final RosterSettings settings;
    try {
      people = items('people').map(Person.fromJson).toList();
      holidays = items('holidays').map(Holiday.fromJson).toList();
      plans = items('monthPlans').map(MonthPlan.fromJson).toList();
      settings = RosterSettings.fromJson(
        (backup['settings'] as Map? ?? const {}).cast<String, dynamic>(),
      );
    } catch (_) {
      throw const BackupFormatException('Yedek dosyası bozuk.');
    }
    final meta = (backup['meta'] as Map? ?? const {}).cast<String, dynamic>();

    await _boxes.people.clear();
    await _boxes.holidays.clear();
    await _boxes.monthPlans.clear();
    await _boxes.settings.clear();
    for (final key in _metaKeys) {
      await _boxes.meta.delete(key);
    }

    await _boxes.people.putAll({for (final p in people) p.id: p});
    await _boxes.holidays.putAll({for (final h in holidays) h.key: h});
    await _boxes.monthPlans.putAll({for (final m in plans) m.key: m});
    await _boxes.settings.put('roster', settings);
    for (final key in _metaKeys) {
      if (meta[key] != null) {
        await _boxes.meta.put(
          key,
          meta[key] is List ? (meta[key] as List).cast<int>() : meta[key],
        );
      }
    }
  }
}
