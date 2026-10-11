import 'package:flutter/material.dart';

import '../../shared/widgets/placeholder_view.dart';

/// Tatiller sekmesi (Level 3'te doldurulacak).
class HolidaysPage extends StatelessWidget {
  const HolidaysPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tatiller')),
      body: const PlaceholderView(
        icon: Icons.celebration_outlined,
        message: 'Resmi tatiller burada listelenecek.',
      ),
    );
  }
}
