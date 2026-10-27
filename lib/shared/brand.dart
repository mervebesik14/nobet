import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Marka renkleri: yeşil degrade başlık, nane tonlu hap etiketler, beyaz
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
    headerStart: Color(0xFF138567),
    headerEnd: Color(0xFF0A5847),
    onHeader: Colors.white,
    onHeaderMuted: Color(0xD9FFFFFF),
    background: Color(0xFFEBF2EF),
    card: Colors.white,
    pill: Color(0xFFD3EAE3),
    onPill: Color(0xFF0D6A54),
    stepper: Color(0xFF117A61),
    stepperValue: Color(0xFF2C9177),
    divider: Color(0xFFE6EEEB),
  );

  static const dark = BrandColors(
    headerStart: Color(0xFF0F5E4C),
    headerEnd: Color(0xFF083A30),
    onHeader: Colors.white,
    onHeaderMuted: Color(0xB3FFFFFF),
    background: Color(0xFF0E1513),
    card: Color(0xFF17211E),
    pill: Color(0xFF1C3A32),
    onPill: Color(0xFF86DCC1),
    stepper: Color(0xFF1B6B57),
    stepperValue: Color(0xFF257E67),
    divider: Color(0xFF243230),
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

/// Uygulamanın teması: DM Sans, marka yeşili, yuvarlak kartlar.
ThemeData brandTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final brand = dark ? BrandColors.dark : BrandColors.light;
  final primary = dark ? const Color(0xFF3DBF99) : const Color(0xFF0F7A61);
  final scheme =
      ColorScheme.fromSeed(
        seedColor: const Color(0xFF0F7A61),
        brightness: brightness,
      ).copyWith(
        primary: primary,
        onPrimary: dark ? const Color(0xFF00382B) : Colors.white,
        surface: brand.card,
        onSurface: dark ? const Color(0xFFE3ECE9) : const Color(0xFF16211D),
        onSurfaceVariant: dark
            ? const Color(0xFF9DB0AA)
            : const Color(0xFF66766F),
        surfaceContainerLowest: brand.background,
        // Bilgi kartları (yedek, ay başı hatırlatması) nane tonunda.
        secondaryContainer: dark
            ? const Color(0xFF1C3A32)
            : const Color(0xFFDDF0EA),
        onSecondaryContainer: dark
            ? const Color(0xFFBFEBDD)
            : const Color(0xFF0D4F40),
        tertiaryContainer: dark
            ? const Color(0xFF173A35)
            : const Color(0xFFD5EEEA),
        onTertiaryContainer: dark
            ? const Color(0xFFB5E6DC)
            : const Color(0xFF0B4A42),
        outlineVariant: brand.divider,
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
    // Alt sayfalar (liste, kişi formu…) düz marka yeşili başlık.
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
      elevation: 0,
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
      thumbColor: const WidgetStatePropertyAll(Colors.white),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected)
            ? brand.stepper
            : (dark ? const Color(0xFF34423E) : const Color(0xFFD3DDD9)),
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
