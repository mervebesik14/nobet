import '../models/day_assignment.dart';
import '../models/person.dart';
import '../models/role.dart';
import '../models/roster_settings.dart';
import 'roster_editor.dart';
import 'roster_validator.dart';

/// Liste onarımının sonucu.
class RosterRepairResult {
  const RosterRepairResult({
    required this.assignments,
    required this.replacements,
    required this.unfilledDays,
  });

  /// Onarılmış atamalar.
  final Map<int, DayAssignment> assignments;

  /// Gün → boşalan koltuğa yazılan kişi.
  final Map<int, String> replacements;

  /// Kurala uygun kimse bulunamadığı için boş kalan günler.
  final List<int> unfilledDays;

  /// Kişinin kaldırılan nöbet sayısı.
  int get removed => replacements.length + unfilledDays.length;
}

/// Bir kişiyi [fromDay]–[toDay] (dahil; [toDay] boşsa ay sonu) günlerinde
/// listeden çıkarır ve boşalan koltukları
/// diğer kişileri en az etkileyecek şekilde doldurur (saf Dart).
///
/// Diğer kişilerin mevcut nöbetlerine dokunulmaz; yalnızca boşalan koltuğa
/// biri eklenir. Aday, o gün yeni bir kural ihlali oluşturmayan (istemediği /
/// izinli gün, art arda gün, gün aşırı zincir, nöbet sınırı) aynı görevdeki
/// kişilerdir. Sorumlu hemşire aday olmaz (yalnızca seçtiği günlerde nöbet
/// tutar). Adaylar arasında bu ay en az nöbeti olan (fazla mesai payı
/// düşülerek), hafta sonu gününde en az hafta sonu nöbeti olan seçilir.
/// Uygun kimse yoksa koltuk boş kalır.
class RosterRepair {
  const RosterRepair._();

  static RosterRepairResult removePerson({
    required int year,
    required int month,
    required Map<int, DayAssignment> assignments,
    required String personId,
    required int fromDay,
    int? toDay,
    required Iterable<Person> people,
    required RosterSettings settings,
    Map<String, List<int>> blockedDays = const {},
    Set<int> weekendDays = const {},
    List<Set<String>> previousMonthTail = const [],
    Set<String> overtimeRequests = const {},
    int overtimeAllowance = 2,
    Map<String, List<int>> requestedShifts = const {},
  }) {
    final validator = RosterValidator(settings);
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final candidates = [
      for (final p in people)
        if (p.id != personId && !p.isChargeNurse && p.worksInMonth(year, month))
          p,
    ]..sort((a, b) => a.id.compareTo(b.id));

    /// Kişi → (eksik koltuk dışındaki) ihlal mesajları.
    Map<String, Set<String>> problems(Map<int, DayAssignment> a) {
      final result = <String, Set<String>>{};
      for (final v in validator.validate(
        year: year,
        month: month,
        assignments: a,
        people: people,
        unavailableDays: blockedDays,
        previousMonthTail: previousMonthTail,
        overtimeRequests: overtimeRequests,
        overtimeAllowance: overtimeAllowance,
        requestedShifts: requestedShifts,
      )) {
        if (v.kind == ViolationKind.missing || v.personId == null) continue;
        (result[v.personId!] ??= {}).add(v.message);
      }
      return result;
    }

    var current = {...assignments};
    final replacements = <int, String>{};
    final unfilled = <int>[];

    final lastDay = toDay == null || toDay > daysInMonth ? daysInMonth : toDay;
    for (var d = fromDay < 1 ? 1 : fromDay; d <= lastDay; d++) {
      final day = current[d];
      if (day == null || !day.includes(personId)) continue;
      final role = day.nurseIds.contains(personId)
          ? Role.nurse
          : Role.radiologyTech;
      final secondary = day.isSecondaryTech(personId);

      current = RosterEditor.replace(
        current,
        day: d,
        role: role,
        oldId: personId,
        nursesPerDay: settings.nursesPerDay,
        secondary: secondary,
      );
      final before = problems(current);

      int shiftsOf(String id) =>
          current.values.where((a) => a.includes(id)).length;
      int weekendShiftsOf(String id) => current.values
          .where((a) => weekendDays.contains(a.day) && a.includes(id))
          .length;

      Person? best;
      Map<int, DayAssignment>? bestResult;
      List<num>? bestRank;
      for (final c in candidates) {
        if (c.role != role) continue;
        if (current[d]?.includes(c.id) ?? false) continue;
        if (blockedDays[c.id]?.contains(d) ?? false) continue;
        final trial = RosterEditor.replace(
          current,
          day: d,
          role: role,
          newId: c.id,
          nursesPerDay: settings.nursesPerDay,
          secondary: secondary,
        );
        final after = problems(trial)[c.id] ?? const <String>{};
        if (!after.every((m) => before[c.id]?.contains(m) ?? false)) {
          continue;
        }
        final rank = <num>[
          shiftsOf(c.id) -
              (overtimeRequests.contains(c.id) ? overtimeAllowance : 0),
          weekendDays.contains(d) ? weekendShiftsOf(c.id) : 0,
        ];
        if (bestRank == null || _less(rank, bestRank)) {
          best = c;
          bestResult = trial;
          bestRank = rank;
        }
      }

      if (best == null) {
        unfilled.add(d);
      } else {
        current = bestResult!;
        replacements[d] = best.id;
      }
    }

    return RosterRepairResult(
      assignments: current,
      replacements: replacements,
      unfilledDays: unfilled,
    );
  }

  static bool _less(List<num> a, List<num> b) {
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return a[i] < b[i];
    }
    return false;
  }
}
