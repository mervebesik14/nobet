import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Marka renkleri: gece mavisi degrade başlık, açık mavi hap etiketler, beyaz
/// kart grupları (Tasarım 3 · "güçlü marka"). Açık ve koyu temada ayrı
/// değerler; `Theme.of(context).extension<BrandColors>()` ya da
/// `context.brand` ile okunur.
@immutable
class BrandColors extends ThemeExtension<BrandColors> {
  const BrandColors({
    required this.headerStart,
    required this.headerEnd,
    required this.onHeader,
    required this.onHeaderMuted,
    required this.background,
    required this.card,
    required this.pill,
    required this.onPill,
    required this.stepper,
    required this.stepperValue,
    required this.divider,
  });

  final Color headerStart;
  final Color headerEnd;
  final Color onHeader;
  final Color onHeaderMuted;
  final Color background;
  final Color card;
  final Color pill;
  final Color onPill;
  final Color stepper;
  final Color stepperValue;
  final Color divider;

  static const light = BrandColors(
    headerStart: Color(0xFF2C4A9A),
    headerEnd: Color(0xFF142659),
    onHeader: Colors.white,
    onHeaderMuted: Color(0xD9FFFFFF),
    background: Color(0xFFEEF1F8),
    card: Colors.white,
    pill: Color(0xFFDCE3F5),
    onPill: Color(0xFF1F3A85),
    stepper: Color(0xFF24438F),
    stepperValue: Color(0xFF3B5DB0),
    divider: Color(0xFFE3E8F2),
  );

  /// Gerçek koyu tasarım: siyaha yakın gece zemini, derin lacivert başlık,
  /// açık mavi vurgular (gece nöbetinde göz yormaz).
  static const dark = BrandColors(
    headerStart: Color(0xFF1B2F66),
    headerEnd: Color(0xFF070E26),
    onHeader: Colors.white,
    onHeaderMuted: Color(0xB3E6EDFF),
    background: Color(0xFF05070D),
    card: Color(0xFF0E1220),
    pill: Color(0xFF141F3D),
    onPill: Color(0xFF9DB6FF),
    stepper: Color(0xFF3E62C8),
    stepperValue: Color(0xFF5A7FE0),
    divider: Color(0xFF1A2133),
  );

  /// Başlık zemini.
  LinearGradient get headerGradient => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [headerStart, headerEnd],
  );

  @override
  BrandColors copyWith() => this;

  @override
  BrandColors lerp(BrandColors? other, double t) {
    if (other == null) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return BrandColors(
      headerStart: c(headerStart, other.headerStart),
      headerEnd: c(headerEnd, other.headerEnd),
      onHeader: c(onHeader, other.onHeader),
      onHeaderMuted: c(onHeaderMuted, other.onHeaderMuted),
      background: c(background, other.background),
      card: c(card, other.card),
      pill: c(pill, other.pill),
      onPill: c(onPill, other.onPill),
      stepper: c(stepper, other.stepper),
      stepperValue: c(stepperValue, other.stepperValue),
      divider: c(divider, other.divider),
    );
  }
}

extension BrandContext on BuildContext {
  BrandColors get brand =>
      Theme.of(this).extension<BrandColors>() ?? BrandColors.light;
}

/// Uygulamanın teması: DM Sans, gece mavisi, yuvarlak kartlar.
ThemeData brandTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final brand = dark ? BrandColors.dark : BrandColors.light;
  final primary = dark ? const Color(0xFF9DB6FF) : const Color(0xFF1F3A85);
  final scheme =
      ColorScheme.fromSeed(
        seedColor: const Color(0xFF1F3A85),
        brightness: brightness,
      ).copyWith(
        primary: primary,
        onPrimary: dark ? const Color(0xFF0A1A45) : Colors.white,
        surface: brand.card,
        onSurface: dark ? const Color(0xFFE8ECF5) : const Color(0xFF141A2A),
        onSurfaceVariant: dark
            ? const Color(0xFF8F98AC)
            : const Color(0xFF626B80),
        surfaceContainerLowest: brand.background,
        // Bilgi kartları (yedek, ay başı hatırlatması) açık mavi tonda.
        secondaryContainer: dark
            ? const Color(0xFF111C38)
            : const Color(0xFFE1E7F6),
        onSecondaryContainer: dark
            ? const Color(0xFFC4D2F5)
            : const Color(0xFF172E6B),
        tertiaryContainer: dark
            ? const Color(0xFF0F1C33)
            : const Color(0xFFDDE6F7),
        onTertiaryContainer: dark
            ? const Color(0xFFB8CBEE)
            : const Color(0xFF16305F),
        outlineVariant: brand.divider,
        // Koyu temada yüzey basamakları siyaha yakın zemine uysun.
        surfaceContainerLow: dark ? const Color(0xFF0B0F1B) : null,
        surfaceContainer: dark ? const Color(0xFF111728) : null,
        surfaceContainerHigh: dark ? const Color(0xFF171E31) : null,
        surfaceContainerHighest: dark ? const Color(0xFF1D2539) : null,
      );
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: 'DM Sans',
  );
  final text = base.textTheme;
  return base.copyWith(
    extensions: [brand],
    scaffoldBackgroundColor: brand.background,
    dividerTheme: DividerThemeData(color: brand.divider, space: 1),
    textTheme: text.copyWith(
      titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      titleSmall: text.titleSmall?.copyWith(fontWeight: FontWeight.w600),
    ),
    // Alt sayfalar (liste, kişi formu…) düz lacivert başlık.
    appBarTheme: AppBarTheme(
      backgroundColor: brand.headerEnd,
      foregroundColor: brand.onHeader,
      elevation: 0,
      scrolledUnderElevation: 0,
      systemOverlayStyle: SystemUiOverlayStyle.light,
      titleTextStyle: text.titleLarge?.copyWith(
        color: brand.onHeader,
        fontWeight: FontWeight.w700,
      ),
    ),
    cardTheme: CardThemeData(
      color: brand.card,
      // Hafif marka tonlu gölge: kartlar zeminden "yüzer".
      elevation: 1.5,
      shadowColor: dark
          ? Colors.black.withValues(alpha: 0.6)
          : brand.headerEnd.withValues(alpha: 0.18),
      surfaceTintColor: Colors.transparent,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
    ),
    listTileTheme: ListTileThemeData(
      titleTextStyle: text.bodyLarge?.copyWith(
        fontWeight: FontWeight.w600,
        color: scheme.onSurface,
      ),
      subtitleTextStyle: text.bodySmall?.copyWith(
        color: scheme.onSurfaceVariant,
      ),
    ),
    switchTheme: SwitchThemeData(
      // Koyu temada kapalı anahtarın topu açık gri.
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) || !dark
            ? Colors.white
            : const Color(0xFFC6CCD9),
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected)
            ? brand.stepper
            : (dark ? const Color(0xFF343C50) : const Color(0xFFD3D9E6)),
      ),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      thumbIcon: const WidgetStatePropertyAll(null),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: brand.stepper,
      foregroundColor: Colors.white,
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      extendedTextStyle: text.titleMedium?.copyWith(
        fontWeight: FontWeight.w700,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: brand.card,
      indicatorColor: brand.pill,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      iconTheme: WidgetStateProperty.resolveWith(
        (s) => IconThemeData(
          color: s.contains(WidgetState.selected)
              ? brand.onPill
              : scheme.onSurfaceVariant,
        ),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => text.labelMedium?.copyWith(
          fontWeight: s.contains(WidgetState.selected)
              ? FontWeight.w700
              : FontWeight.w500,
          color: s.contains(WidgetState.selected)
              ? scheme.onSurface
              : scheme.onSurfaceVariant,
        ),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: brand.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    bottomSheetTheme: BottomSheetThemeData(backgroundColor: brand.card),
  );
}
