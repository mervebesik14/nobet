import 'package:flutter/material.dart';

import 'brand_widgets.dart';

/// Kişi listesi bölüm başlığı: hap içinde başlık, yanında "8 kişi".
class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.title, required this.count});

  final String title;
  final int count;

  @override
  Widget build(BuildContext context) =>
      PillHeader(title, trailing: '$count kişi');
}
