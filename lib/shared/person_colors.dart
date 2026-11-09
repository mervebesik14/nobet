import 'package:flutter/material.dart';

import '../models/models.dart';

/// Kişi renkleri: kişide renk seçilmişse o, yoksa kimliğinden her zaman
/// aynı çıkan bir palet rengi. Liste, Bugün kartı, kişiler ve istatistikte
/// aynı renk kullanılır.
class PersonColors {
  const PersonColors._();

  /// Beyaz yazının okunduğu doygun tonlar.
  static const palette = [
    Color(0xFF0F7A61),
    Color(0xFF2E6FD8),
    Color(0xFF8E44AD),
    Color(0xFFD35400),
    Color(0xFFC2185B),
    Color(0xFF00838F),
    Color(0xFF6D4C41),
    Color(0xFF3949AB),
    Color(0xFF558B2F),
    Color(0xFFAD1457),
    Color(0xFF00695C),
    Color(0xFFEF6C00),
  ];

  /// [id]'den kararlı palet rengi.
  static Color forId(String id) {
    var h = 0;
    for (final c in id.codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    return palette[h % palette.length];
  }

  static Color of(Person p) =>
      p.colorValue != null ? Color(p.colorValue!) : forId(p.id);

  /// "Ayşe Yılmaz" → "AY", "Banu" → "B".
  static String initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    final first = parts.first.characters.first;
    if (parts.length == 1) return first.toUpperCase();
    return '$first${parts.last.characters.first}'.toUpperCase();
  }
}

/// Kişinin renkli baş harf avatarı.
class PersonAvatar extends StatelessWidget {
  const PersonAvatar({
    super.key,
    required this.name,
    required this.color,
    this.radius = 18,
    this.ring = false,
  });

  PersonAvatar.of(Person person, {Key? key, double radius = 18})
    : this(
        key: key,
        name: person.name,
        color: PersonColors.of(person),
        radius: radius,
      );

  final String name;
  final Color color;
  final double radius;

  /// Dışta beyaz halka (üst üste dizilen avatarlar için).
  final bool ring;

  @override
  Widget build(BuildContext context) {
    final avatar = Container(
      width: radius * 2,
      height: radius * 2,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color.lerp(color, Colors.white, 0.18)!, color],
        ),
        border: ring
            ? Border.all(color: Theme.of(context).colorScheme.surface, width: 2)
            : null,
      ),
      child: Text(
        PersonColors.initials(name),
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: radius * 0.72,
          height: 1,
        ),
      ),
    );
    return avatar;
  }
}
