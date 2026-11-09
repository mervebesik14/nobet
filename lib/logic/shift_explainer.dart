import '../models/models.dart';
import 'block_reason.dart';
import 'every_other_day_chains.dart';
import 'turkish_collation.dart';
import 'turkish_dates.dart';

/// Aynı roldeki bir kişinin o gün neden nöbette olmadığı.
typedef OtherReason = ({String personId, String name, String reason});

/// "Neden bu nöbet?" açıklaması.
class ShiftExplanation {
  const ShiftExplanation({
    required this.title,
    required this.facts,
    required this.warnings,
    required this.others,
  });

  /// "Ayşe · 12 Ekim Pazartesi"
  final String title;

  /// Kişiyle ilgili bilgiler (bu ayki nöbet sayısı, hafta sonu, istekler).
  final List<String> facts;

  /// Kişinin kendisi için kural uyarıları (ör. elle istemediği güne yazıldı).
  final List<String> warnings;

  /// Aynı roldeki diğer kişiler neden o gün değil.
  final List<OtherReason> others;
}

/// Bir nöbetin neden o kişiye düştüğünü, listenin şu anki hâline bakarak
/// açıklar (saf Dart). Kesin kurallar (izin, istemediği gün, art arda,
/// gün aşırı zincir) önce; ardından ay içi denge (nöbet ve hafta sonu
/// sayısı). Liste elle değiştirildiyse açıklama da o anki duruma göredir.
class ShiftExplainer {
  const ShiftExplainer._();

  static ShiftExplanation explain({
    required MonthPlan plan,
    required Iterable<Person> people,
    required String personId,
    required int day,
    required RosterSettings settings,
    Map<String, Map<int, BlockReason>> blockReasons = const {},
    Set<int> weekendDays = const {},
  }) {
    final byId = {for (final p in people) p.id: p};
    final person = byId[personId];
    final role = person?.role ?? Role.nurse;
    final dateLabel = formatDayMonthWeekday(plan.year, plan.month, day);
    final title = '${person?.name ?? 'Silinmiş kişi'} · $dateLabel';

    Set<int> daysOf(String id) => {
      for (final a in plan.assignments.values)
        if (a.includes(id)) a.day,
    };
    int weekendOf(String id) => daysOf(id).where(weekendDays.contains).length;

    // Aynı roldeki, bu ay çalışan diğerleri (sorumlu hemşire ayrı ele alınır).
    final group = [
      for (final p in people)
        if (p.role == role && p.worksInMonth(plan.year, plan.month)) p,
    ];
    final fair = [
      for (final p in group)
        if (!p.isChargeNurse) p,
    ];
    final mine = daysOf(personId);
    final isWeekend = weekendDays.contains(day);
    String avg(num Function(String) pick) {
      if (fair.isEmpty) return '0';
      final v =
          fair.map((p) => pick(p.id)).fold<num>(0, (s, x) => s + x) /
          fair.length;
      return v == v.roundToDouble()
          ? v.toInt().toString()
          : v.toStringAsFixed(1).replaceAll('.', ',');
    }

    final facts = <String>[
      if (plan.requestedShifts[personId]?.contains(day) ?? false)
        'Bu gün, kişinin kendi seçtiği nöbet günü.',
      if (person?.isChargeNurse ?? false)
        'Sorumlu hemşire: ortalamaya eşitlenmez, yalnız seçtiği günlerde '
            'nöbet tutar.'
      else
        'Bu ay ${mine.length} nöbeti var; ${role.label.toLowerCase()} '
            'ortalaması ${avg((id) => daysOf(id).length)}.',
      if (isWeekend && !(person?.isChargeNurse ?? false))
        'Hafta sonu nöbeti ${weekendOf(personId)}; ortalama '
            '${avg(weekendOf)}.',
      if (plan.wantsOvertime(personId))
        'Bu ay fazla mesai istedi; ortalamadan birkaç fazla nöbet alabilir.',
      if (EveryOtherDayChains.of(mine).where((c) => c.contains(day))
          case final chains when chains.isNotEmpty)
        'Gün aşırı zincirin parçası: '
            '${EveryOtherDayChains.format(chains.first)}.',
    ];

    final warnings = <String>[
      if (blockReasons[personId]?[day] case final r?)
        'Dikkat: ${r.label} (elle yazılmış olabilir).',
      if (settings.forbidConsecutiveDays && mine.contains(day - 1))
        'Dikkat: bir gün önce de nöbette (art arda).',
      if (settings.forbidConsecutiveDays && mine.contains(day + 1))
        'Dikkat: ertesi gün de nöbette (art arda).',
    ];

    final current = plan.assignments[day];
    final others = <OtherReason>[];
    for (final p in group) {
      if (p.id == personId || (current?.includes(p.id) ?? false)) continue;
      final days = daysOf(p.id);
      final String reason;
      if (blockReasons[p.id]?[day] case final r?) {
        reason = r.label;
      } else if (p.isChargeNurse) {
        reason = 'sorumlu hemşire; yalnız seçtiği günlerde nöbet tutar';
      } else if (settings.forbidConsecutiveDays && days.contains(day - 1)) {
        reason =
            'bir gün önce (${formatDayMonth(day - 1, plan.month)}) '
            'nöbette';
      } else if (settings.forbidConsecutiveDays && days.contains(day + 1)) {
        reason =
            'ertesi gün (${formatDayMonth(day + 1, plan.month)}) '
            'nöbette';
      } else if (_chainWith(days, day) > settings.maxEveryOtherDayChain) {
        reason =
            'gün aşırı zinciri ${_chainWith(days, day)} nöbete çıkardı '
            '(en fazla ${settings.maxEveryOtherDayChain})';
      } else if (days.length >= mine.length) {
        reason =
            'bu ay zaten ${days.length} nöbeti var '
            '(${person?.name ?? 'kişi'}: bununla ${mine.length})';
      } else if (isWeekend && weekendOf(p.id) >= weekendOf(personId)) {
        reason =
            'hafta sonu nöbeti zaten ${weekendOf(p.id)} '
            '(${person?.name ?? 'kişi'}: bununla ${weekendOf(personId)})';
      } else if (plan.wantsOvertime(personId) && !plan.wantsOvertime(p.id)) {
        reason = 'fazla mesai istemedi';
      } else {
        reason =
            'kural engeli yok; nöbet aralıkları ve yıl içi denge '
            'gereği başka günlere yazıldı';
      }
      others.add((personId: p.id, name: p.name, reason: reason));
    }
    // Kesin engeller önce, sonra adalet gerekçeleri; kendi içinde ada göre.
    int rank(OtherReason o) => o.reason.startsWith('kural engeli yok')
        ? 2
        : o.reason.startsWith('bu ay zaten') ||
              o.reason.startsWith('hafta sonu') ||
              o.reason.startsWith('fazla mesai')
        ? 1
        : 0;
    others.sort((a, b) {
      final r = rank(a).compareTo(rank(b));
      return r != 0 ? r : compareTurkish(a.name, b.name);
    });

    return ShiftExplanation(
      title: title,
      facts: facts,
      warnings: warnings,
      others: others,
    );
  }

  /// [day] eklenince onu içeren gün aşırı zincirin uzunluğu (yoksa 1).
  static int _chainWith(Set<int> days, int day) {
    for (final c in EveryOtherDayChains.of({...days, day})) {
      if (c.contains(day)) return c.length;
    }
    return 1;
  }
}
