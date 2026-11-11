import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';

/// Rapor girilince kişinin o günlerdeki nöbetlerine ne yapılacağı.
enum SickShiftAction {
  ask('Sor'),
  vacate('Boş bırak'),
  redistribute('Otomatik dağıt');

  const SickShiftAction(this.label);
  final String label;
}

/// Ayarlardaki tercih (`app_meta` sickShiftAction); varsayılan "Sor".
class SickShiftActionNotifier extends Notifier<SickShiftAction> {
  static const _key = 'sickShiftAction';

  @override
  SickShiftAction build() {
    final v = ref.watch(hiveBoxesProvider).meta.get(_key);
    return SickShiftAction.values.firstWhere(
      (a) => a.name == v,
      orElse: () => SickShiftAction.ask,
    );
  }

  Future<void> set(SickShiftAction action) async {
    state = action;
    await ref.read(hiveBoxesProvider).meta.put(_key, action.name);
  }
}

final sickShiftActionProvider =
    NotifierProvider<SickShiftActionNotifier, SickShiftAction>(
      SickShiftActionNotifier.new,
    );
