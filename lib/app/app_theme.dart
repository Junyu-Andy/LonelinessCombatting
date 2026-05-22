import 'package:flutter/material.dart';

/// Global theme tokens for the warm-restyle pass.
///
/// Font assets to be bundled in `assets/fonts/` and registered in
/// `pubspec.yaml` under `flutter.fonts:` (families: `NotoSerifHK` for
/// headlines/titles/display; `NotoSansHK` for body/label). Until the
/// font files ship, Flutter falls back to system fonts — the `fontFamily`
/// strings below are harmless when assets are missing.
class AppTheme {
  // Warm terracotta seed.
  static const Color _seed = Color(0xFFC2703F);
  // Warm ink primary text.
  static const Color _ink = Color(0xFF3A3330);
  // Warm grey secondary text.
  static const Color _inkMuted = Color(0xFF8A7D72);
  // Warm off-white background.
  static const Color _surface = Color(0xFFF7F5F1);
  // Lighter, warm outline.
  static const Color _outline = Color(0xFFE7E0D8);

  /// Soft, warm-toned card shadow (≈ rgba(150,120,95,0.08)).
  static const BoxShadow softCardShadow = BoxShadow(
    color: Color(0x14967860),
    blurRadius: 12,
    offset: Offset(0, 3),
  );

  /// Subtle top shadow used by the bottom navigation bar.
  static const BoxShadow navTopShadow = BoxShadow(
    color: Color(0x0D967860), // rgba(150,120,95,0.05)
    blurRadius: 8,
    offset: Offset(0, -2),
  );

  static ThemeData get light => _build(highContrast: false);

  static ThemeData get highContrast => _build(highContrast: true);

  static ThemeData _build({required bool highContrast}) {
    final Color ink = highContrast ? Colors.black : _ink;
    final Color inkMuted = highContrast ? Colors.black : _inkMuted;
    final Color surface = highContrast ? Colors.white : _surface;
    final Color cardColor = Colors.white;
    final Color primary = highContrast ? Colors.black : _seed;
    final Color outline = highContrast ? Colors.black : _outline;

    final baseScheme = ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: Brightness.light,
    );
    final colorScheme = baseScheme.copyWith(
      primary: primary,
      onPrimary: Colors.white,
      onSurface: ink,
      onSurfaceVariant: inkMuted,
      outline: outline,
      outlineVariant: outline,
    );

    const String serifFamily = 'NotoSerifHK';
    const String sansFamily = 'NotoSansHK';

    final baseTextTheme = ThemeData.light().textTheme;
    final textTheme = baseTextTheme
        .copyWith(
          displayLarge: baseTextTheme.displayLarge?.copyWith(
            fontFamily: serifFamily,
          ),
          displayMedium: baseTextTheme.displayMedium?.copyWith(
            fontFamily: serifFamily,
          ),
          displaySmall: baseTextTheme.displaySmall?.copyWith(
            fontFamily: serifFamily,
            fontSize: 36,
            fontWeight: FontWeight.w700,
            height: 1.2,
          ),
          headlineLarge: baseTextTheme.headlineLarge?.copyWith(
            fontFamily: serifFamily,
            fontSize: 32,
            fontWeight: FontWeight.w700,
            // P4-polish: bumped to 1.4 — multi-line Chinese headlines
            // were touching at 1.25 for elderly readers.
            height: 1.4,
          ),
          headlineMedium: baseTextTheme.headlineMedium?.copyWith(
            fontFamily: serifFamily,
            fontSize: 28,
            fontWeight: FontWeight.w700,
            height: 1.4,
          ),
          headlineSmall: baseTextTheme.headlineSmall?.copyWith(
            fontFamily: serifFamily,
            fontSize: 24,
            fontWeight: FontWeight.w600,
            height: 1.4,
          ),
          titleLarge: baseTextTheme.titleLarge?.copyWith(
            fontFamily: serifFamily,
            fontSize: 22,
            fontWeight: FontWeight.w600,
            height: 1.35,
          ),
          titleMedium: baseTextTheme.titleMedium?.copyWith(
            fontFamily: serifFamily,
            fontSize: 20,
            fontWeight: FontWeight.w600,
            height: 1.35,
          ),
          titleSmall: baseTextTheme.titleSmall?.copyWith(
            fontFamily: serifFamily,
          ),
          bodyLarge: baseTextTheme.bodyLarge?.copyWith(
            fontFamily: sansFamily,
            fontSize: 20,
            height: 1.55,
          ),
          bodyMedium: baseTextTheme.bodyMedium?.copyWith(
            fontFamily: sansFamily,
            fontSize: 18,
            height: 1.55,
          ),
          bodySmall: baseTextTheme.bodySmall?.copyWith(
            fontFamily: sansFamily,
            fontSize: 16,
            height: 1.5,
          ),
          labelLarge: baseTextTheme.labelLarge?.copyWith(
            fontFamily: sansFamily,
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
          labelMedium: baseTextTheme.labelMedium?.copyWith(
            fontFamily: sansFamily,
          ),
          labelSmall: baseTextTheme.labelSmall?.copyWith(
            fontFamily: sansFamily,
          ),
        )
        .apply(bodyColor: ink, displayColor: ink);

    final borderWidth = highContrast ? 2.0 : 1.0;

    // High contrast retains the original 2px black border, no shadow.
    // Normal mode drops the border and relies on the soft warm shadow
    // (applied at the widget level via `softCardShadow` since CardTheme
    // does not natively support custom shadow lists).
    final cardShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(22),
      side: highContrast
          ? BorderSide(color: outline, width: borderWidth)
          : BorderSide.none,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: surface,
      textTheme: textTheme,
      visualDensity: VisualDensity.comfortable,
      iconTheme: IconThemeData(size: 28, color: ink),
      primaryIconTheme: IconThemeData(size: 28, color: ink),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        toolbarHeight: 72,
        backgroundColor: surface,
        foregroundColor: ink,
        titleTextStyle: textTheme.headlineSmall,
        iconTheme: IconThemeData(size: 32, color: ink),
      ),
      cardTheme: CardThemeData(
        elevation: highContrast ? 0 : 2,
        margin: EdgeInsets.zero,
        color: cardColor,
        surfaceTintColor: Colors.transparent,
        shadowColor: const Color(0x14967860),
        shape: cardShape,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 60),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          textStyle: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(0, 60),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          textStyle: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 60),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          textStyle: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
          side: BorderSide(color: colorScheme.primary, width: 2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(0, 56),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          textStyle: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
        ),
      ),
      chipTheme: ChipThemeData(
        labelStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w500),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        backgroundColor: cardColor,
        side: BorderSide(color: outline, width: borderWidth),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: cardColor,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
        hintStyle: TextStyle(fontSize: 18, color: inkMuted),
        labelStyle: const TextStyle(fontSize: 18),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: outline, width: borderWidth),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: outline, width: borderWidth),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: primary, width: borderWidth + 1),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 88,
        backgroundColor: cardColor,
        // Selected indicator is the warm terracotta primary in both modes
        // so the active tab reads clearly against the warm off-white bg.
        indicatorColor: highContrast
            ? primary
            : _seed.withValues(alpha: 0.18),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontFamily: sansFamily,
            fontSize: 15,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? primary : inkMuted,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            size: 30,
            color: selected
                ? (highContrast ? Colors.white : primary)
                : inkMuted,
          );
        }),
      ),
      sliderTheme: const SliderThemeData(
        trackHeight: 8,
      ),
    );
  }
}
