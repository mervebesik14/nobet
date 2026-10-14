import 'dart:math';

import '../models/person.dart';
import '../models/role.dart';
import '../models/roster_settings.dart';
import 'turkish_collation.dart';
import 'turkish_dates.dart';

/// Uygunluk sorununun türü.
enum FeasibilityIssueKind {
  /// Rolde hiç aktif kişi yok.
  noPeople,

  /// Bir günde o rolde yeterli uygun kişi yok.
  dayShortage,

  /// Art arda gün yasağı yüzünden iki ardışık güne yetecek kişi yok.
  pairShortage,

  /// Ay boyunca gereken nöbet, kuralların izin verdiği toplamı aşıyor.
  capacity,
}

/// Liste oluşturmadan önce bulunan bir sorun.
class FeasibilityIssue {
  const FeasibilityIssue({
    required this.kind,
    required this.role,
    required this.message,
    this.day,
  });

  final FeasibilityIssueKind kind;
  final Role role;

  /// Sorunun başladığı gün (gün bazlı sorunlarda).
  final int? day;

  /// Türkçe açıklama, ör. "14 Ekim: uygun tekniker yok."
  final String message;

  @override
  String toString() => message;
}

class FeasibilityReport {
  const FeasibilityReport(this.issues);

  final List<FeasibilityIssue> issues;

  bool get isFeasible => issues.isEmpty;
}

/// Nöbet listesi oluşturmadan önce kişiler, istenmeyen günler ve kurallarla
/// listenin kurulabilir olup olmadığını kontrol eder.
///
/// Bulduğu her sorun kesin bir engeldir; ama sorun bulamaması listenin
/// kesin kurulabileceğini göstermez (kişiler arası etkileşimler burada
/// tam hesaplanmaz).
class FeasibilityChecker {
  const FeasibilityChecker(this.settings);

  final RosterSettings settings;

  FeasibilityReport check({
    required int year,
    required int month,
    required Iterable<Person> people,
    required Map<String, List<int>> unavailableDays,
    Map<String, List<int>> requestedShifts = const {},
  }) {
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final issues = <FeasibilityIssue>[];

    for (final role in Role.values) {
      final perDay = _perDay(role);
      if (perDay <= 0) continue;
      final members = people.where(
        (p) => p.worksInMonth(year, month) && p.role == role,
      );
      // Sorumlu hemşire yalnızca seçtiği nöbet günlerinde uygun sayılır.
      final available = {
        for (final p in members)
          p.id: {
            for (var d = 1; d <= daysInMonth; d++)
              if (!(unavailableDays[p.id] ?? const []).contains(d) &&
                  (!p.isChargeNurse ||
                      (requestedShifts[p.id]?.contains(d) ?? false)))
                d,
          },
      };

      if (available.isEmpty) {
        issues.add(
          FeasibilityIssue(
            kind: FeasibilityIssueKind.noPeople,
            role: role,
            message: 'Hiç aktif ${turkishLowerCase(role.label)} yok.',
          ),
        );
        continue;
      }

      issues
        ..addAll(_dayShortages(role, perDay, available, month, daysInMonth))
        ..addAll(_pairShortages(role, perDay, available, month, daysInMonth))
        ..addAll(_capacity(role, perDay, available, daysInMonth));
    }
    return FeasibilityReport(issues);
  }

  int _perDay(Role role) => switch (role) {
    Role.nurse => settings.nursesPerDay,
    Role.radiologyTech => settings.techsPerDay,
  };

  String _date(int month, int day) => formatDayMonth(day, month);

  int _availableOn(Map<String, Set<int>> available, int day) =>
      available.values.where((days) => days.contains(day)).length;

  Iterable<FeasibilityIssue> _dayShortages(
    Role role,
    int perDay,
    Map<String, Set<int>> available,
    int month,
    int daysInMonth,
  ) sync* {
    final label = turkishLowerCase(role.label);
    for (var d = 1; d <= daysInMonth; d++) {
      final count = _availableOn(available, d);
      if (count >= perDay) continue;
      yield FeasibilityIssue(
        kind: FeasibilityIssueKind.dayShortage,
        role: role,
        day: d,
        message: count == 0
            ? '${_date(month, d)}: uygun $label yok.'
            : '${_date(month, d)}: uygun $label sayısı $count, '
                  'gereken $perDay.',
      );
    }
  }

  /// Art arda gün yasağında d ve d+1'in nöbetçileri farklı kişiler olmalı,
  /// yani iki günde birden en az 2 × günlük sayı kadar kişi uygun olmalı.
  /// Tek gün yetersizliği zaten ayrıca raporlandığı için burada atlanır.
  Iterable<FeasibilityIssue> _pairShortages(
    Role role,
    int perDay,
    Map<String, Set<int>> available,
    int month,
    int daysInMonth,
  ) sync* {
    if (!settings.forbidConsecutiveDays) return;
    for (var d = 1; d < daysInMonth; d++) {
      if (_availableOn(available, d) < perDay ||
          _availableOn(available, d + 1) < perDay) {
        continue;
      }
      final either = available.values
          .where((days) => days.contains(d) || days.contains(d + 1))
          .length;
      if (either >= 2 * perDay) continue;
      yield FeasibilityIssue(
        kind: FeasibilityIssueKind.pairShortage,
        role: role,
        day: d,
        message:
            '${_date(month, d)} – ${_date(month, d + 1)}: art arda gün '
            'yasağı nedeniyle iki güne ${2 * perDay} farklı '
            '${turkishLowerCase(role.label)} gerekiyor, uygun olan $either.',
      );
    }
  }

  Iterable<FeasibilityIssue> _capacity(
    Role role,
    int perDay,
    Map<String, Set<int>> available,
    int daysInMonth,
  ) sync* {
    final needed = daysInMonth * perDay;
    final n = available.length;

    int capacity({required bool consecutive, required bool chain}) => available
        .values
        .map(
          (days) => maxShifts(
            days,
            daysInMonth,
            forbidConsecutive: consecutive,
            maxChain: chain ? settings.maxEveryOtherDayChain : null,
          ),
        )
        .fold(0, (a, b) => a + b);

    final withRules = capacity(
      consecutive: settings.forbidConsecutiveDays,
      chain: true,
    );
    final cap = settings.maxExtraOverAverage == null
        ? null
        : (needed / n).ceil() + settings.maxExtraOverAverage!;
    final withCap = cap == null
        ? withRules
        : available.values
              .map(
                (days) => min(
                  cap,
                  maxShifts(
                    days,
                    daysInMonth,
                    forbidConsecutive: settings.forbidConsecutiveDays,
                    maxChain: settings.maxEveryOtherDayChain,
                  ),
                ),
              )
              .fold(0, (a, b) => a + b);

    if (withCap >= needed) return;

    final label = turkishLowerCase(role.pluralLabel);
    final base = 'Bu ay $label için $needed nöbet gerekiyor ($n kişi)';
    final plain = capacity(consecutive: false, chain: false);

    final String reason;
    if (plain < needed) {
      reason =
          'istenmeyen günler çıkarıldığında en fazla $plain nöbet '
          'tutulabilir. Kişi ekleyin ya da istenmeyen günleri azaltın.';
    } else if (withRules >= needed) {
      reason =
          'fazla nöbet sınırı (grup ortalaması + '
          '${settings.maxExtraOverAverage}) ile en fazla $withCap nöbet '
          'tutulabilir. Bu sınırı artırın ya da kapatın.';
    } else {
      final consecutiveOnly = settings.forbidConsecutiveDays
          ? capacity(consecutive: true, chain: false)
          : plain;
      final chainOnly = capacity(consecutive: false, chain: true);
      final rules = <String>[
        if (settings.forbidConsecutiveDays && consecutiveOnly < needed)
          'art arda gün yasağı',
        if (chainOnly < needed) 'gün aşırı zincir sınırı',
      ];
      final ruleText = rules.isEmpty
          ? 'art arda gün yasağı ile gün aşırı zincir sınırı birlikte'
          : rules.join(' ve ');
      reason =
          '$ruleText yüzünden en fazla $withRules nöbet tutulabilir. '
          'Kişi ekleyin ya da bu kuralı ayarlardan gevşetin.';
    }

    yield FeasibilityIssue(
      kind: FeasibilityIssueKind.capacity,
      role: role,
      message: '$base; $reason',
    );
  }

  /// Bir kişinin [availableDays] günlerinde, kurallara uyarak bu ay en fazla
  /// kaç nöbet tutabileceği.
  ///
  /// [forbidConsecutive]: art arda iki gün yok. [maxChain]: gün aşırı
  /// zincirde en fazla bu kadar nöbet (2 ise d, d+2, d+4 üçü birden yok);
  /// boşsa sınır yok.
  static int maxShifts(
    Set<int> availableDays,
    int daysInMonth, {
    required bool forbidConsecutive,
    int? maxChain,
  }) {
    final chain = maxChain == null ? null : max(1, maxChain);
    // Durum: son `window` günün nöbet bitleri (bit 0 = dün).
    final window = chain == null ? 1 : 2 * chain;
    final mask = (1 << window) - 1;
    var best = <int, int>{0: 0};

    bool chainBroken(int state) {
      if (chain == null) return false;
      // d-2, d-4, ..., d-2*chain günlerinin hepsi nöbetse bugün yasak.
      for (var k = 1; k <= chain; k++) {
        if (state & (1 << (2 * k - 1)) == 0) return false;
      }
      return true;
    }

    for (var d = 1; d <= daysInMonth; d++) {
      final next = <int, int>{};
      void put(int state, int value) {
        if ((next[state] ?? -1) < value) next[state] = value;
      }

      for (final MapEntry(key: state, value: count) in best.entries) {
        put((state << 1) & mask, count);
        final canWork =
            availableDays.contains(d) &&
            !(forbidConsecutive && state & 1 == 1) &&
            !chainBroken(state);
        if (canWork) put(((state << 1) | 1) & mask, count + 1);
      }
      best = next;
    }
    return best.values.fold(0, max);
  }
}
