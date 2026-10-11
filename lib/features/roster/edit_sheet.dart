import 'package:flutter/material.dart';

import '../../models/models.dart';

/// Düzenleme alt sayfasındaki bir seçenek: uygulanırsa ortaya çıkacak
/// atamalar ve yeni kural ihlalleri.
class EditOption {
  const EditOption({
    required this.title,
    required this.result,
    this.warnings = const [],
    this.subtitle,
    this.icon,
  });

  final String title;
  final Map<int, DayAssignment> result;

  /// Bu seçenek seçilirse çıkacak yeni ihlaller (boşsa kurala uygun).
  final List<String> warnings;
  final String? subtitle;
  final IconData? icon;

  bool get isValid => warnings.isEmpty;
}

/// Hücreye dokununca açılan alt sayfa. Kurala uygun seçenekler üstte,
/// kural bozacaklar uyarı ikonu ve sebebiyle altta. Seçilen seçeneğin
/// atamalarını döndürür.
Future<Map<int, DayAssignment>?> showEditSheet(
  BuildContext context, {
  required String title,
  String? subtitle,
  List<EditOption> actions = const [],
  String? candidatesTitle,
  List<EditOption> candidates = const [],
}) {
  final sorted = [...candidates]
    ..sort((a, b) => (a.isValid ? 0 : 1).compareTo(b.isValid ? 0 : 1));
  return showModalBottomSheet<Map<int, DayAssignment>>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) {
      final theme = Theme.of(context);
      Widget tile(EditOption o) => ListTile(
        leading: Icon(
          o.icon ??
              (o.isValid
                  ? Icons.check_circle_outline
                  : Icons.warning_amber_rounded),
          color: o.isValid ? theme.colorScheme.primary : Colors.orange,
        ),
        title: Text(o.title),
        subtitle: o.warnings.isEmpty && o.subtitle == null
            ? null
            : Text([?o.subtitle, ...o.warnings].join('\n')),
        onTap: () => Navigator.of(context).pop(o.result),
      );
      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        builder: (context, controller) => ListView(
          controller: controller,
          children: [
            ListTile(
              title: Text(title, style: theme.textTheme.titleMedium),
              subtitle: subtitle == null ? null : Text(subtitle),
            ),
            ...actions.map(tile),
            if (candidates.isNotEmpty) ...[
              if (candidatesTitle != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Text(
                    candidatesTitle,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
              ...sorted.map(tile),
            ],
            const SizedBox(height: 16),
          ],
        ),
      );
    },
  );
}
