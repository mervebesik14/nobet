import '../models/models.dart';
import 'turkish_collation.dart';

/// Ekip kuralları (saf Dart): birlikte / ayrı çiftleri ([PairRule]) ve
/// kıdem ([Seniority]). "Ayrı" çift aynı gün nöbet tutmaz (kesin);
/// "birlikte" çift mümkünse aynı gün (tercih); yeni başlayanın yanında
/// aynı rolden en az bir kıdemli olmalı (koltuk boş kalmayacaksa).
class TeamRules {
  TeamRules(Iterable<Person> people, List<PairRule> rules) {
    for (final p in people) {
      if (p.seniority == Seniority.senior) seniors.add(p.id);
      if (p.seniority == Seniority.novice) novices.add(p.id);
    }
    for (final r in rules) {
      if (r.a == r.b) continue;
      final map = r.together ? together : apart;
      (map[r.a] ??= {}).add(r.b);
      (map[r.b] ??= {}).add(r.a);
    }
  }

  final Map<String, Set<String>> apart = {};
  final Map<String, Set<String>> together = {};
  final Set<String> seniors = {};
  final Set<String> novices = {};

  bool get isEmpty => apart.isEmpty && together.isEmpty && novices.isEmpty;

  bool isApart(String a, String b) => apart[a]?.contains(b) ?? false;

  bool isTogether(String a, String b) => together[a]?.contains(b) ?? false;

  /// Aynı güne yazılmış "ayrı" çiftler.
  List<(String, String)> apartClashes(List<String> ids) => [
    for (var i = 0; i < ids.length; i++)
      for (var j = i + 1; j < ids.length; j++)
        if (isApart(ids[i], ids[j])) (ids[i], ids[j]),
  ];

  /// Aynı güne yazılmış "birlikte" çift sayısı.
  int togetherHits(List<String> ids) {
    var n = 0;
    for (var i = 0; i < ids.length; i++) {
      for (var j = i + 1; j < ids.length; j++) {
        if (isTogether(ids[i], ids[j])) n++;
      }
    }
    return n;
  }

  /// Yanında kıdemli olmayan yeni başlayanlar ([ids] aynı rolün o günkü
  /// nöbetçileri).
  List<String> unsupervised(List<String> ids) =>
      ids.any(seniors.contains) ? const [] : [...ids.where(novices.contains)];

  /// Kuralların düz cümleleri (ayarlar ve belgeler için).
  static List<String> describe(List<PairRule> rules, Iterable<Person> people) {
    final names = {for (final p in people) p.id: p.name};
    final lines = [
      for (final r in rules)
        if (names[r.a] != null && names[r.b] != null)
          r.together
              ? '${names[r.a]} ile ${names[r.b]} mümkünse aynı gün.'
              : '${names[r.a]} ile ${names[r.b]} aynı gün nöbet tutmaz.',
    ];
    final novices = [
      for (final p in people)
        if (p.seniority == Seniority.novice && p.isActive) p.name,
    ]..sort(compareTurkish);
    if (novices.isNotEmpty) {
      lines.add(
        '${novices.join(', ')}: yeni başlayan; yanında en az bir kıdemli '
        'olur.',
      );
    }
    return lines;
  }
}
