import 'package:flutter/material.dart';

class AppTheme {
  static const Color _seed = Color(0xFF1D4ED8);
  static const Color _ink = Color(0xFF0F172A);
  static const Color _inkMuted = Color(0xFF334155);
  static const Color _surface = Color(0xFFF8FAFC);

  static ThemeData get light => _build(highContrast: false);

  static ThemeData get highContrast => _build(highContrast: true);

  static ThemeData _build({required bool highContrast}) {
    final Color ink = highContrast ? Colors.black : _ink;
    final Color inkMuted = highContrast ? Colors.black : _inkMuted;
    final Color surface = highContrast ? Colors.white : _surface;
    final Color cardColor = Colors.white;
    final Color primary = highContrast ? Colors.black : _seed;
    final Color outline = highContrast ? Colors.black : const Color(0xFFCBD5E1);

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

    final baseTextTheme = ThemeData.light().textTheme;
    final textTheme = baseTextTheme
        .copyWith(
          displaySmall: baseTextTheme.displaySmall?.copyWith(
            fontSize: 36,
            fontWeight: FontWeight.w700,
            height: 1.2,
          ),
          headlineLarge: baseTextTheme.headlineLarge?.copyWith(
            fontSize: 32,
            fontWeight: FontWeight.w700,
            height: 1.25,
          ),
          headlineMedium: baseTextTheme.headlineMedium?.copyWith(
            fontSize: 28,
            fontWeight: FontWeight.w700,
            height: 1.3,
          ),
          headlineSmall: baseTextTheme.headlineSmall?.copyWith(
            fontSize: 24,
            fontWeight: FontWeight.w600,
            height: 1.3,
          ),
          titleLarge: baseTextTheme.titleLarge?.copyWith(
            fontSize: 22,
            fontWeight: FontWeight.w600,
            height: 1.35,
          ),
          titleMedium: baseTextTheme.titleMedium?.copyWith(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            height: 1.35,
          ),
          bodyLarge: baseTextTheme.bodyLarge?.copyWith(
            fontSize: 20,
            height: 1.55,
          ),
          bodyMedium: baseTextTheme.bodyMedium?.copyWith(
            fontSize: 18,
            height: 1.55,
          ),
          bodySmall: baseTextTheme.bodySmall?.copyWith(
            fontSize: 16,
            height: 1.5,
          ),
          labelLarge: baseTextTheme.labelLarge?.copyWith(
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        )
        .apply(bodyColor: ink, displayColor: ink);

    final borderWidth = highContrast ? 2.0 : 1.0;

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
        elevation: 0,
        margin: EdgeInsets.zero,
        color: cardColor,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: outline, width: borderWidth),
        ),
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
        indicatorColor: highContrast ? primary : colorScheme.primaryContainer,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
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
