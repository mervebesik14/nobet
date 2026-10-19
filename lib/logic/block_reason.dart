/// Bir kişinin bir güne nöbete yazılamamasının nedeni (saf Dart).
///
/// Sıra önceliktir: aynı gün birden çok neden varsa listede önce gelen
/// gösterilir (ör. hem izinli hem istemediği gün → izin).
enum BlockReason {
  annualLeave('yıllık izinde', 'yıllık izinli olduğu güne'),
  radiationLeave('şua izninde', 'şua izninde olduğu güne'),
  sickLeave('raporlu', 'raporlu olduğu güne'),
  inactive('pasif', 'pasif olduğu güne'),
  unavailable('istemediği gün', 'istemediği güne'),
  beforeAnnualLeave('yıllık izin öncesi', 'yıllık izninden hemen önceki güne'),
  afterAnnualLeave(
    'yıllık izin dönüşü',
    'yıllık izin dönüşü ilk iş gününden önceki güne',
  ),
  beforeRadiationLeave(
    'şua izni öncesi',
    'şua izninden önceki iki günden birine',
  ),
  afterRadiationLeave(
    'şua izni dönüşü',
    'şua izni dönüşü ilk iş gününden önceki güne',
  );

  const BlockReason(this.label, this.target);

  /// Kısa açıklama, ör. aday listesinde "yıllık izinde".
  final String label;

  /// İhlal cümlesindeki hedef, ör. "… istemediği güne (16 Ekim) atandı."
  final String target;

  /// "Fatih Işık yıllık izinli olduğu güne (16 Ekim) atandı." gibi cümle;
  /// izin öncesi/sonrası için kuralı da açıklar.
  String message(String name, String date) => switch (this) {
    beforeAnnualLeave =>
      '$name $target ($date) atandı. Yıllık izinden önceki son nöbet, '
          'izinden önceki son iş gününden bir önceki gün olmalı.',
    afterAnnualLeave =>
      '$name $target ($date) atandı. Yıllık izinden sonra ilk nöbet ilk '
          'iş gününde olabilir.',
    beforeRadiationLeave =>
      '$name $target ($date) atandı. Şua izninden önceki iki gün nöbet '
          'tutulmaz.',
    afterRadiationLeave =>
      '$name $target ($date) atandı. Şua izninden sonra ilk nöbet ilk '
          'iş gününde olabilir.',
    _ => '$name $target ($date) atandı.',
  };

  /// Kişi → gün → neden haritalarını birleştirir; aynı güne düşen
  /// nedenlerden önceliklisi kalır.
  static Map<String, Map<int, BlockReason>> combine(
    Map<BlockReason, Map<String, Iterable<int>>> sources,
  ) {
    final result = <String, Map<int, BlockReason>>{};
    for (final reason in BlockReason.values.reversed) {
      for (final MapEntry(key: id, value: days)
          in (sources[reason] ?? const {}).entries) {
        for (final d in days) {
          (result[id] ??= {})[d] = reason;
        }
      }
    }
    result.removeWhere((_, days) => days.isEmpty);
    return result;
  }

  /// Kişi → sıralı kapalı günler.
  static Map<String, List<int>> days(
    Map<String, Map<int, BlockReason>> reasons,
  ) => {
    for (final MapEntry(key: id, value: days) in reasons.entries)
      id: days.keys.toList()..sort(),
  };
}
