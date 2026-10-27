import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../logic/turkish_collation.dart';
import '../brand.dart';

/// Sekme ekranlarının yeşil degrade başlığı: büyük başlık, isteğe bağlı alt
/// yazı, sağda yuvarlak düğmeler ve altta ay/yıl seçici gibi bir alan.
/// `Scaffold.appBar` olarak kullanılır.
class BrandHeader extends StatelessWidget implements PreferredSizeWidget {
  const BrandHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
    this.bottom,
    this.footer,
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;

  /// Başlığın altında, ör. [HeaderSelector].
  final Widget? bottom;

  /// En altta küçük açıklama satırı (ör. "Dahil aylar: …").
  final String? footer;

  @override
  Size get preferredSize => Size.fromHeight(
    12 +
        48 +
        (subtitle != null ? 24 : 0) +
        (bottom != null ? 60 : 0) +
        (footer != null ? 26 : 0) +
        20,
  );

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final text = Theme.of(context).textTheme;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Container(
        decoration: BoxDecoration(
          gradient: brand.headerGradient,
          borderRadius: const BorderRadius.vertical(
            bottom: Radius.circular(28),
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 16, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: 48,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.headlineMedium?.copyWith(
                            color: brand.onHeader,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      for (final a in actions) ...[const SizedBox(width: 8), a],
                    ],
                  ),
                ),
                if (subtitle != null)
                  SizedBox(
                    height: 24,
                    child: Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodyMedium?.copyWith(
                        color: brand.onHeaderMuted,
                      ),
                    ),
                  ),
                if (bottom != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12, right: 4),
                    child: SizedBox(height: 48, child: bottom),
                  ),
                if (footer != null)
                  SizedBox(
                    height: 26,
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: Text(
                        footer!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.bodySmall?.copyWith(
                          color: brand.onHeaderMuted,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Başlıktaki yarı saydam, köşeleri yuvarlak kare düğme.
class HeaderIconButton extends StatelessWidget {
  const HeaderIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon),
      color: brand.onHeader,
      style: IconButton.styleFrom(
        backgroundColor: brand.onHeader.withValues(alpha: 0.14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        fixedSize: const Size(44, 44),
      ),
    );
  }
}

/// Başlıktaki "‹ Ekim 2026 ›" seçici.
class HeaderSelector extends StatelessWidget {
  const HeaderSelector({
    super.key,
    required this.label,
    required this.onPrevious,
    required this.onNext,
    required this.previousTooltip,
    required this.nextTooltip,
  });

  final String label;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final String previousTooltip;
  final String nextTooltip;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    Widget arrow(IconData icon, String tooltip, VoidCallback onTap) =>
        IconButton(
          tooltip: tooltip,
          onPressed: onTap,
          icon: Icon(icon, size: 20),
          color: brand.onHeader,
          style: IconButton.styleFrom(
            backgroundColor: brand.onHeader.withValues(alpha: 0.14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            fixedSize: const Size(36, 36),
            minimumSize: const Size(36, 36),
          ),
        );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: brand.onHeader.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          arrow(Icons.chevron_left, previousTooltip, onPrevious),
          Expanded(
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: brand.onHeader,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          arrow(Icons.chevron_right, nextTooltip, onNext),
        ],
      ),
    );
  }
}

/// Başlıkta ay seçici.
class HeaderMonthSelector extends StatelessWidget {
  const HeaderMonthSelector({
    super.key,
    required this.month,
    required this.onChanged,
  });

  final DateTime month;
  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) => HeaderSelector(
    label: DateFormat.yMMMM('tr_TR').format(month),
    previousTooltip: 'Önceki ay',
    nextTooltip: 'Sonraki ay',
    onPrevious: () => onChanged(DateTime(month.year, month.month - 1)),
    onNext: () => onChanged(DateTime(month.year, month.month + 1)),
  );
}

/// Bölüm başlığı: nane tonlu hap içinde büyük harfli başlık, yanında
/// isteğe bağlı açıklama ("8 kişi").
class PillHeader extends StatelessWidget {
  const PillHeader(this.title, {super.key, this.trailing, this.end});

  final String title;

  /// Hapın hemen yanında (ör. "8 kişi").
  final String? trailing;

  /// Satırın en sağında (ör. "Toplam nöbet · yıl").
  final String? end;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      fontWeight: FontWeight.w600,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: brand.pill,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              turkishUpperCase(title),
              style: theme.textTheme.labelMedium?.copyWith(
                color: brand.onPill,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
              ),
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 10),
            Text(trailing!, style: muted),
          ],
          if (end != null) ...[const Spacer(), Text(end!, style: muted)],
        ],
      ),
    );
  }
}

/// Beyaz, köşeleri yuvarlak kart içinde aralarında çizgi olan satırlar.
class GroupCard extends StatelessWidget {
  const GroupCard({super.key, required this.children, this.dividerIndent = 16});

  final List<Widget> children;
  final double dividerIndent;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    return Card(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                indent: dividerIndent,
                endIndent: dividerIndent,
              ),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// Dolgulu marka sayacı: "− 2 +".
class BrandStepper extends StatelessWidget {
  const BrandStepper({
    super.key,
    required this.label,
    required this.onDecrement,
    required this.onIncrement,
    required this.decrementTooltip,
    required this.incrementTooltip,
  });

  final String label;
  final VoidCallback? onDecrement;
  final VoidCallback? onIncrement;
  final String decrementTooltip;
  final String incrementTooltip;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final text = Theme.of(context).textTheme;
    Widget button(IconData icon, String tooltip, VoidCallback? onTap) =>
        Tooltip(
          message: tooltip,
          child: InkWell(
            onTap: onTap,
            child: SizedBox(
              width: 36,
              height: 36,
              child: Icon(
                icon,
                size: 20,
                color: onTap == null
                    ? Colors.white.withValues(alpha: 0.35)
                    : Colors.white,
              ),
            ),
          ),
        );
    return Material(
      color: brand.stepper,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          button(Icons.remove, decrementTooltip, onDecrement),
          Container(
            constraints: const BoxConstraints(minWidth: 48),
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            alignment: Alignment.center,
            color: brand.stepperValue,
            child: Text(
              label,
              style: text.labelLarge?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          button(Icons.add, incrementTooltip, onIncrement),
        ],
      ),
    );
  }
}

/// Alt kısımda kalan alan: başlıkla ilk kart arasındaki boşluk.
const brandListPadding = EdgeInsets.only(top: 4, bottom: 24);
