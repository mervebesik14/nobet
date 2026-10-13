import 'package:flutter/material.dart';

import '../app_colors.dart';

/// Liste bölüm başlığı: başlık ve yanında sayı rozeti.
class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.title, required this.count});

  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Row(
        children: [
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(width: 8),
          Badge(
            label: Text('$count'),
            backgroundColor: theme.colorScheme.infoTint,
            textColor: theme.colorScheme.primary,
          ),
        ],
      ),
    );
  }
}
