import 'package:hive_ce/hive_ce.dart';

import '../models/models.dart';

/// Tek bir [RosterSettings] kaydını saklar.
class SettingsRepository {
  SettingsRepository(this._box);

  static const _key = 'roster';

  final Box<RosterSettings> _box;

  /// Kayıtlı ayarlar; hiç kaydedilmediyse varsayılanlar.
  RosterSettings load() => _box.get(_key) ?? const RosterSettings();

  Future<void> save(RosterSettings settings) => _box.put(_key, settings);

  /// Varsayılanlara döner.
  Future<void> reset() => _box.delete(_key);

  Stream<BoxEvent> watch() => _box.watch(key: _key);
}
