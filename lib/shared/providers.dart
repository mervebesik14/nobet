import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Bugünün tarihi. Testlerde sabit bir günle override edilir.
final todayProvider = Provider<DateTime>((ref) => DateTime.now());

/// Yeni liste oluştururken kullanılan tohum kaynağı. Testlerde sabit
/// tohumlu bir kaynakla override edilir; böylece sonuçlar tekrarlanabilir.
final rosterSeedProvider = Provider<int Function()>((ref) {
  final rng = Random();
  return () => rng.nextInt(1 << 31);
});
