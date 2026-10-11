import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../shared/widgets/placeholder_view.dart';

/// Ay Planı sekmesi (Level 4'te doldurulacak).
class MonthPage extends StatelessWidget {
  const MonthPage({super.key});

  @override
  Widget build(BuildContext context) {
    // Türkçe tarih biçimini doğrulamak için içinde bulunulan ay gösterilir.
    final currentMonth = DateFormat.yMMMM('tr_TR').format(DateTime.now());

    return Scaffold(
      appBar: AppBar(title: const Text('Ay Planı')),
      body: PlaceholderView(
        icon: Icons.calendar_month_outlined,
        message: '$currentMonth\nAy planı henüz oluşturulmadı.',
      ),
    );
  }
}
