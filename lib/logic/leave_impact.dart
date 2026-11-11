import '../models/models.dart';
import 'feasibility_checker.dart';
import 'turkish_collation.dart';
import 'turkish_dates.dart';

/// İzin eklemeden önceki değerlendirme sonucu.
enum LeaveVerdict { ok, caution, problem }

/// [LeaveImpact.assess] sonucu.
class LeaveImpactReport {
  const LeaveImpactReport({
    required this.verdict,
    required this.affectedDays,
    required this.shortDays,
    required this.tightDays,
    required this.others,
    required this.extraShifts,
    required this.extraPerPerson,
    required this.rosterShifts,
    required this.newIssues,
    required this.lines,
  });

  final LeaveVerdict verdict;

  /// Kişinin izinle yeni kapanan günleri (izin öncesi/sonrası kurallar
  /// dahil).
  final List<int> affectedDays;

  /// Bu günlerde rolde yeterli uygun kişi kalmıyor (koltuk boş kalır).
  final List<int> shortDays;

  /// Uygun kişi ancak yetiyor (ya da bir fazlası).
  final List<int> tightDays;

  /// Aynı günlerde müsait olmayan diğerleri: ad → gün sayısı.
  final Map<String, int> others;

  /// Kişinin payından diğerlerine kayan tahmini nöbet.
  final double extraShifts;
  final double extraPerPerson;

  /// Listede bu günlerde zaten yazılı nöbetleri.
  final List<int> rosterShifts;

  /// İzinle yeni çıkan uygunluk sorunları.
  final List<String> newIssues;

  /// Kullanıcıya gösterilecek satırlar.
  final List<String> lines;
}

/// İzin onay asistanı (saf Dart): bir kişiye izin vermeden önce ayın
/// kurulabilirliğine, aynı roldeki diğerlerine ve listeye etkisi.
class LeaveImpact {
  const LeaveImpact._();

  /// [blockedBefore] / [blockedAfter]: izin eklenmeden önce ve sonra kişi →
  /// nöbet tutamayacağı günler (izin, istemediği gün, pasif, izin
  /// kuralları).
  static LeaveImpactReport assess({
    required int year,
    required int month,
    required Iterable<Person> people,
    required String personId,
    required Map<String, List<int>> blockedBefore,
    required Map<String, List<int>> blockedAfter,
    required RosterSettings settings,
    Map<String, List<int>> requestedShifts = const {},
    Map<int, DayAssignment> assignments = const {},
  }) {
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final person = people.firstWhere((p) => p.id == personId);
    final role = person.role;
    final perDay = role == Role.nurse
        ? settings.nursesPerDay
        : settings.techsPerDay;
    final members = [
      for (final p in people)
        if (p.role == role && !p.isChargeNurse && p.worksInMonth(year, month))
          p,
    ];
    final before = (blockedBefore[personId] ?? const []).toSet();
    final affected = [
      for (final d in (blockedAfter[personId] ?? const []).toSet())
        if (!before.contains(d)) d,
    ]..sort();

    int available(int d) => members
        .where((p) => !(blockedAfter[p.id]?.contains(d) ?? false))
        .length;

    final short = <int>[], tight = <int>[];
    for (final d in affected) {
      final n = available(d);
      if (n < perDay) {
        short.add(d);
      } else if (n <= perDay + 1) {
        tight.add(d);
      }
    }

    final others = <String, int>{};
    for (final p in members) {
      if (p.id == personId) continue;
      final blocked = blockedAfter[p.id];
      if (blocked == null) continue;
      final n = affected.where(blocked.contains).length;
      if (n > 0) others[p.name] = n;
    }
    final sortedOthers = Map.fromEntries(
      others.entries.toList()..sort((a, b) {
        final c = b.value.compareTo(a.value);
        return c != 0 ? c : compareTurkish(a.key, b.key);
      }),
    );

    final fair = members.length;
    final share = fair == 0 || person.isChargeNurse
        ? 0.0
        : daysInMonth * perDay / fair;
    final extra = share * affected.length / daysInMonth;
    final perPerson = fair > 1 ? extra / (fair - 1) : 0.0;

    final rosterShifts = [
      for (final d in affected)
        if (assignments[d]?.includes(personId) ?? false) d,
    ];

    final checker = FeasibilityChecker(settings);
    List<String> issues(Map<String, List<int>> blocked) => [
      for (final i
          in checker
              .check(
                year: year,
                month: month,
                people: people,
                unavailableDays: blocked,
                requestedShifts: requestedShifts,
              )
              .issues)
        if (i.role == role) i.message,
    ];
    final had = issues(blockedBefore).toSet();
    final fresh = [
      for (final m in issues(blockedAfter))
        if (!had.contains(m)) m,
    ];

    String days(List<int> ds) =>
        '${ds.map((d) => '$d').join(', ')} ${turkishMonthNames[month - 1]}';
    String num(double v) => v.toStringAsFixed(1).replaceAll('.', ',');
    final roleName = role.label.toLowerCase();

    final lines = [
      if (affected.isEmpty)
        'Bu ay nöbet tutabileceği günlerde değişiklik olmuyor.'
      else
        '${affected.length} gün nöbete kapanır: ${days(affected)}.',
      if (short.isNotEmpty)
        'Koltuk boş kalır: ${days(short)} (yeterli $roleName yok).',
      if (tight.isNotEmpty)
        'Sıkışık günler: ${days(tight)} (uygun $roleName ancak yetiyor).',
      ...fresh,
      if (sortedOthers.isNotEmpty)
        'Aynı günlerde müsait olmayanlar: '
            '${sortedOthers.entries.map((e) => '${e.key} (${e.value} gün)').join(', ')}.',
      if (extra >= 0.1)
        'Diğerlerine yaklaşık ${num(extra)} nöbet daha düşer '
            '(kişi başı ${num(perPerson)}).',
      if (rosterShifts.isNotEmpty)
        'Listede bu günlerde ${rosterShifts.length} nöbeti var '
            '(${days(rosterShifts)}); yerine biri yazılmalı.',
    ];

    final verdict = short.isNotEmpty || fresh.isNotEmpty
        ? LeaveVerdict.problem
        : tight.isNotEmpty || rosterShifts.isNotEmpty
        ? LeaveVerdict.caution
        : LeaveVerdict.ok;

    return LeaveImpactReport(
      verdict: verdict,
      affectedDays: affected,
      shortDays: short,
      tightDays: tight,
      others: sortedOthers,
      extraShifts: extra,
      extraPerPerson: perPerson,
      rosterShifts: rosterShifts,
      newIssues: fresh,
      lines: lines,
    );
  }
}
