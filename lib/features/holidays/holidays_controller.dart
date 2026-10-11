import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/holiday_repository.dart';
import '../../data/providers.dart';
import '../../models/models.dart';
import '../../shared/providers.dart';

/// Tüm tatiller, tarihe göre sıralı.
class HolidaysController extends Notifier<List<Holiday>> {
  @override
  List<Holiday> build() => ref.watch(holidayRepositoryProvider).getAll();

  /// Bu günde kayıtlı tatil var mı?
  bool isTaken(DateTime date) =>
      state.any((h) => h.key == Holiday.keyFor(date));

  Future<void> add(Holiday holiday) => _run((r) => r.save(holiday));

  Future<void> toggleHalfDay(Holiday holiday) =>
      _run((r) => r.save(holiday.copyWith(isHalfDay: !holiday.isHalfDay)));

  Future<void> delete(Holiday holiday) => _run((r) => r.delete(holiday.date));

  /// [year] yılının hazır Türkiye tatillerini ilk seferde yükler.
  Future<void> ensureYearSeeded(int year) =>
      _run((r) => r.ensureYearSeeded(year));

  Future<void> _run(Future<void> Function(HolidayRepository) action) async {
    final repo = ref.read(holidayRepositoryProvider);
    await action(repo);
    state = repo.getAll();
  }
}

final holidaysProvider = NotifierProvider<HolidaysController, List<Holiday>>(
  HolidaysController.new,
);

/// Tatiller ekranında seçili ay (ayın 1'i).
class HolidayMonthController extends Notifier<DateTime> {
  @override
  DateTime build() {
    final today = ref.watch(todayProvider);
    return DateTime(today.year, today.month);
  }

  /// Ayı değiştirir; yeni yılın hazır tatilleri henüz yüklenmediyse yükler.
  Future<void> select(DateTime month) async {
    state = DateTime(month.year, month.month);
    await ref.read(holidaysProvider.notifier).ensureYearSeeded(month.year);
  }
}

final holidayMonthProvider = NotifierProvider<HolidayMonthController, DateTime>(
  HolidayMonthController.new,
);
