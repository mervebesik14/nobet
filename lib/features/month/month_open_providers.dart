import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../data/providers.dart';
import '../../logic/month_open.dart';
import '../../logic/recurring_requests.dart';
import 'month_plan_controller.dart';

/// Kalıcı istekler (`app_meta` recurringRequests).
class RecurringRequestsNotifier extends Notifier<List<RecurringRequest>> {
  static const _key = 'recurringRequests';
  static const _uuid = Uuid();

  @override
  List<RecurringRequest> build() {
    final raw = ref.watch(hiveBoxesProvider).meta.get(_key);
    if (raw is! List) return const [];
    return [
      for (final r in raw)
        if (r is Map) RecurringRequest.fromJson(r.cast<String, dynamic>()),
    ];
  }

  Future<void> _save(List<RecurringRequest> list) async {
    state = list;
    await ref.read(hiveBoxesProvider).meta.put(_key, [
      for (final r in list) r.toJson(),
    ]);
  }

  Future<void> add({
    required String personId,
    Set<int> weekdays = const {},
    Set<int> monthDays = const {},
    DateTime? until,
  }) => _save([
    ...state,
    RecurringRequest(
      id: _uuid.v4(),
      personId: personId,
      weekdays: weekdays,
      monthDays: monthDays,
      until: until,
    ),
  ]);

  Future<void> remove(String id) => _save([
    for (final r in state)
      if (r.id != id) r,
  ]);
}

final recurringRequestsProvider =
    NotifierProvider<RecurringRequestsNotifier, List<RecurringRequest>>(
      RecurringRequestsNotifier.new,
    );

/// Seçili ayda isteğini yazmış (cevap vermiş) kişiler.
class RequestRepliesNotifier extends Notifier<Set<String>> {
  String get _key {
    final plan = ref.read(monthPlanProvider);
    return MonthOpen.repliesKey(plan.year, plan.month);
  }

  @override
  Set<String> build() {
    final plan = ref.watch(monthPlanProvider);
    final raw = ref
        .watch(hiveBoxesProvider)
        .meta
        .get(MonthOpen.repliesKey(plan.year, plan.month));
    return raw is List ? {...raw.whereType<String>()} : const {};
  }

  Future<void> _save(Set<String> ids) async {
    state = ids;
    await ref.read(hiveBoxesProvider).meta.put(_key, ids.toList());
  }

  Future<void> mark(Iterable<String> ids) => _save({...state, ...ids});

  Future<void> toggle(String id) =>
      _save(state.contains(id) ? ({...state}..remove(id)) : {...state, id});
}

final requestRepliesProvider =
    NotifierProvider<RequestRepliesNotifier, Set<String>>(
      RequestRepliesNotifier.new,
    );
