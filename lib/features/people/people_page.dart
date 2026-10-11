import 'package:flutter/material.dart';

import '../../shared/widgets/placeholder_view.dart';

/// Kişiler sekmesi (Level 2'de doldurulacak).
class PeoplePage extends StatelessWidget {
  const PeoplePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Kişiler')),
      body: const PlaceholderView(
        icon: Icons.people_outline,
        message: 'Henüz kişi eklenmedi.',
      ),
    );
  }
}
