/// Nöbet tutan personelin görevi.
enum Role {
  nurse('Hemşire'),
  radiologyTech('Radyoloji Teknikeri');

  const Role(this.label);

  /// Arayüzde görünen Türkçe ad.
  final String label;

  /// JSON'daki adından rolü bulur.
  static Role fromName(String name) => Role.values.byName(name);
}
