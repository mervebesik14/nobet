/// Kişinin kıdemi; "yeni başlayan"ın her nöbetinde yanında aynı rolden en
/// az bir kıdemli olmalı.
enum Seniority {
  normal('Normal'),
  senior('Kıdemli'),
  novice('Yeni başlayan');

  const Seniority(this.label);

  final String label;

  static Seniority fromName(String? name) => Seniority.values.firstWhere(
    (s) => s.name == name,
    orElse: () => Seniority.normal,
  );
}
