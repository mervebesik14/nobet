import 'package:flutter/material.dart';

import '../../shared/widgets/placeholder_view.dart';

/// Ayarlar sekmesi (Level 9'da doldurulacak).
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ayarlar')),
      body: const PlaceholderView(
        icon: Icons.settings_outlined,
        message: 'Kurallar, tema ve yedekleme ayarları burada olacak.',
      ),
    );
  }
}
