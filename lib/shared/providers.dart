import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Bugünün tarihi. Testlerde sabit bir günle override edilir.
final todayProvider = Provider<DateTime>((ref) => DateTime.now());
