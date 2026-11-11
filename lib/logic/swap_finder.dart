import '../models/models.dart';
import 'roster_editor.dart';
import 'roster_validator.dart';
import 'turkish_collation.dart';
import 'turkish_dates.dart';

/// Önerilen bir takas: [personId] [day] nöbetini [otherId]'nin [otherDay]
/// nöbetiyle değiştirir.
typedef SwapOption = ({
  String otherId,
  String otherName,
  int otherDay,
  Map<int, DayAssignment> after,
});

/// Takas önerici (saf Dart): kişinin bir nöbeti için, aynı roldeki
/// diğerlerinin nöbetleriyle yapılabilecek ve yeni kural ihlali
/// doğurmayan takaslar. Sıra: yakın tarih önce, hafta sonu dengesini
/// bozmayan önce, sonra ada göre.
class SwapFinder {
  const SwapFinder._();

  /// Takasta yeni çıkmaması gereken kurallar.
  static const hardKinds = {
    ViolationKind.unavailable,
    ViolationKind.consecutive,
    ViolationKind.chain,
    ViolationKind.overCap,
    ViolationKind.wrongRole,
    ViolationKind.chargeNurseUnrequested,
    ViolationKind.radiationReturn,
  };

  /// Sayısı artmaması gereken uyarılar (boşluklar).
  static const softKinds = {
    ViolationKind.longGap,
    ViolationKind.unevenFiveGaps,
  };

  static List<SwapOption> find({
    required MonthPlan plan,
    required Iterable<Person> people,
    required String personId,
    required int day,
    required int nursesPerDay,
    required List<RuleViolation> Function(Map<int, DayAssignment>) validate,
    Set<int> weekendDays = const {},
    Map<String, int> debts = const {},
    int limit = 12,
  }) {
    final current = plan.assignments[day];
    if (current == null || !current.includes(personId)) return const [];
    final role = current.nurseIds.contains(personId)
        ? Role.nurse
        : Role.radiologyTech;
    final beforeList = validate(plan.assignments);
    final before = {
      for (final v in beforeList)
        if (hardKinds.contains(v.kind)) v.message,
    };
    int soft(Iterable<RuleViolation> vs) =>
        vs.where((v) => softKinds.contains(v.kind)).length;
    final softBefore = soft(beforeList);
    final out = <(SwapOption, int)>[];
    for (final q in people) {
      if (q.id == personId || q.role != role || current.includes(q.id)) {
        continue;
      }
      for (final a in plan.assignments.values) {
        final e = a.day;
        if (e == day || !a.includes(q.id) || a.includes(personId)) continue;
        // 16B koltukları kendi aralarında takas edilir.
        if (a.isSecondaryTech(q.id) != current.isSecondaryTech(personId)) {
          continue;
        }
        final Map<int, DayAssignment> after;
        try {
          after = RosterEditor.swap(
            plan.assignments,
            a: personId,
            dayA: day,
            b: q.id,
            dayB: e,
            role: role,
            nursesPerDay: nursesPerDay,
          );
        } on RosterEditException {
          continue;
        }
        final afterList = validate(after);
        // Kesin kurallarda yeni ihlal yok, boşluk uyarıları artmıyor.
        final fresh = afterList.where(
          (v) => hardKinds.contains(v.kind) && !before.contains(v.message),
        );
        if (fresh.isNotEmpty || soft(afterList) > softBefore) continue;
        // Hafta sonu dengesi: biri hafta sonunu verip hafta içi alıyorsa
        // küçük ceza (iki kişinin hafta sonu sayısı değişir).
        final weekendShift =
            weekendDays.contains(day) != weekendDays.contains(e) ? 1 : 0;
        out.add((
          (otherId: q.id, otherName: q.name, otherDay: e, after: after),
          // Kişiye iyilik borcu olan önce (bkz. FavorLedger).
          -(debts[q.id] ?? 0) * 1000 + weekendShift * 100 + (e - day).abs(),
        ));
      }
    }
    out.sort((x, y) {
      final r = x.$2.compareTo(y.$2);
      return r != 0 ? r : compareTurkish(x.$1.otherName, y.$1.otherName);
    });
    return [for (final o in out.take(limit)) o.$1];
  }

  /// Takas teklifi mesajı (öteki kişiye).
  static String offer({
    required MonthPlan plan,
    required String personName,
    required int day,
    required String otherName,
    required int otherDay,
  }) {
    String d(int x) => formatDayMonthWeekday(plan.year, plan.month, x);
    return 'Merhaba $otherName, $personName ${d(day)} nöbetini seninle '
        'değiştirmek istiyor: sen ${d(day)}, $personName ${d(otherDay)} '
        'nöbetini tutacak. Uygun musun?';
  }
}
