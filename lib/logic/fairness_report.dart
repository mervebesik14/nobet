import '../models/models.dart';
import 'person_totals.dart';
import 'request_fulfillment.dart';
import 'roster_summary.dart';
import 'shift_gaps.dart';

/// Adalet belgesinde bir kişinin satırı.
typedef FairnessRow = ({
  String personId,
  String name,
  Role role,
  bool isChargeNurse,
  int shifts,
  int weekend,
  int preWeekend,
  int holiday,
  int pairs,
  int ytdShifts,
  int ytdWeekend,
  int ytdHoliday,
  int requestsMet,
  int requestsTotal,
});

/// Bir rolde bir ölçünün en çok ve en az arasındaki fark.
typedef FairnessCheck = ({String label, int spread});

/// "Liste nasıl dağıtıldı" belgesinin verisi (saf Dart): kişi başı bu ay ve
/// yıl içi sayılar, rol içi farklar, istek karşılanma ve uygulanan
/// kurallar. Listeyle birlikte paylaşılır; "bana hep kötü günler düşüyor"
/// tartışmasını sayıyla cevaplar.
class FairnessReport {
  const FairnessReport({
    required this.rows,
    required this.checks,
    required this.rules,
    required this.requestsMet,
    required this.requestsTotal,
  });

  /// Rol sırasıyla, her rolde ada göre (özetteki sıra).
  final List<FairnessRow> rows;

  /// Rol → ölçü farkları (sorumlu hemşire hariç).
  final Map<Role, List<FairnessCheck>> checks;

  /// Uygulanan kurallar, düz cümleler.
  final List<String> rules;

  final int requestsMet;
  final int requestsTotal;

  /// Fark bu kadar ya da azsa dengeli sayılır.
  static const balanced = 1;

  /// [ytd]: yılbaşından bu ay dahil kişi toplamları; [requests]: bu ayın
  /// istekleri ([RequestFulfillment.forMonth]).
  factory FairnessReport.build({
    required RosterSummary summary,
    required Map<String, PersonTotals> ytd,
    required Map<String, List<RequestItem>> requests,
    required RosterSettings settings,
  }) {
    final rows = <FairnessRow>[
      for (final p in summary.people)
        (
          personId: p.personId,
          name: p.name,
          role: p.role,
          isChargeNurse: p.isChargeNurse,
          shifts: p.shifts,
          weekend: p.weekendShifts,
          preWeekend: p.preWeekendShifts,
          holiday: p.nationalHolidayShifts + p.religiousHolidayShifts,
          pairs: p.everyOtherDayPairs,
          ytdShifts: ytd[p.personId]?.shifts ?? p.shifts,
          ytdWeekend: ytd[p.personId]?.weekendShifts ?? p.weekendShifts,
          ytdHoliday: ytd[p.personId] == null
              ? p.nationalHolidayShifts + p.religiousHolidayShifts
              : ytd[p.personId]!.nationalHolidayShifts +
                    ytd[p.personId]!.religiousHolidayShifts,
          requestsMet: (requests[p.personId] ?? const [])
              .where((i) => i.met)
              .length,
          requestsTotal: (requests[p.personId] ?? const []).length,
        ),
    ];
    final checks = <Role, List<FairnessCheck>>{};
    for (final role in Role.values) {
      final group = [
        for (final r in rows)
          if (r.role == role && !r.isChargeNurse) r,
      ];
      if (group.length < 2) continue;
      int spread(int Function(FairnessRow) pick) {
        final v = group.map(pick).toList()..sort();
        return v.last - v.first;
      }

      checks[role] = [
        (label: 'Toplam nöbet', spread: spread((r) => r.shifts)),
        (label: 'Hafta sonu', spread: spread((r) => r.weekend)),
        (label: 'Cuma nöbeti', spread: spread((r) => r.preWeekend)),
        (label: 'Tatil / bayram', spread: spread((r) => r.holiday)),
        (label: 'Gün aşırı çift', spread: spread((r) => r.pairs)),
      ];
    }
    return FairnessReport(
      rows: rows,
      checks: checks,
      rules: rulesOf(settings),
      requestsMet: rows.fold(0, (s, r) => s + r.requestsMet),
      requestsTotal: rows.fold(0, (s, r) => s + r.requestsTotal),
    );
  }

  /// Ayarlara göre uygulanan kurallar.
  static List<String> rulesOf(RosterSettings s) => [
    'İstemediği gün, izin, rapor ve şua günlerinde kimseye nöbet yazılmaz.',
    if (s.forbidConsecutiveDays) 'Kimse art arda iki gün nöbet tutmaz.',
    'Gün aşırı en fazla ${s.maxEveryOtherDayChain} nöbet arka arkaya '
        'gelir.',
    'İki nöbet arasında en fazla ${ShiftGaps.maxGap} gün boşluk kalır '
        '(koltuk boş kalacaksa aşılır).',
    'Toplam, hafta sonu, Cuma, resmi tatil ve bayram nöbetleri rol içinde '
        'eşitlenir (fark en fazla 1).',
    'Bu ay eşit olunca fazla nöbet, yıl içinde payından az tutana verilir; '
        'pay, izinli ve pasif günler düşülerek hesaplanır.',
    'Geçen sefer aynı bayramda tutanlar bu sefer en son yazılır.',
    if (s.holidayCountsAsWeekend) 'Resmi tatiller hafta sonu sayılır.',
    if (s.maxExtraOverAverage case final n?)
      'Kimse rol ortalamasından $n nöbetten fazla tutmaz.',
  ];

  /// Rolün denge cümlesi: "Toplam nöbet 1 · Hafta sonu 0 · ...".
  static String checkLine(List<FairnessCheck> checks) =>
      [for (final c in checks) '${c.label} farkı ${c.spread}'].join(' · ');

  /// Bütün ölçüler dengeli mi?
  bool balancedFor(Role role) =>
      (checks[role] ?? const []).every((c) => c.spread <= balanced);

  /// 0–100; istek yoksa 100.
  int get requestPercent =>
      requestsTotal == 0 ? 100 : (requestsMet * 100 / requestsTotal).round();
}
