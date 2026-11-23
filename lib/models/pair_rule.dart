/// İki kişi arasındaki kural: [together] ise mümkünse aynı gün nöbet
/// tutarlar (tercih), değilse aynı gün asla nöbet tutmazlar (kesin).
class PairRule {
  const PairRule({required this.a, required this.b, this.together = false});

  final String a;
  final String b;
  final bool together;

  bool involves(String id) => a == id || b == id;

  /// [id]'nin eşi; kuralda değilse null.
  String? partnerOf(String id) => a == id
      ? b
      : b == id
      ? a
      : null;

  /// Aynı iki kişi (sıra fark etmez).
  bool samePair(PairRule o) => (a == o.a && b == o.b) || (a == o.b && b == o.a);

  Map<String, dynamic> toJson() => {'a': a, 'b': b, 'together': together};

  factory PairRule.fromJson(Map<String, dynamic> json) => PairRule(
    a: json['a'] as String,
    b: json['b'] as String,
    together: json['together'] as bool? ?? false,
  );

  @override
  bool operator ==(Object other) =>
      other is PairRule &&
      other.a == a &&
      other.b == b &&
      other.together == together;

  @override
  int get hashCode => Object.hash(a, b, together);
}
