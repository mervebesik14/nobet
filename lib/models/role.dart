/// Nöbet tutan personelin görevi.
enum Role {
  nurse('Hemşire', 'Hemşireler'),
  radiologyTech('Radyoloji Teknikeri', 'Radyoloji Teknikerleri');

  const Role(this.label, this.pluralLabel);

  /// Arayüzde görünen Türkçe ad.
  final String label;

  /// Grup başlıklarında kullanılan çoğul ad.
  final String pluralLabel;

  /// JSON'daki adından rolü bulur.
  static Role fromName(String name) => Role.values.byName(name);
}
