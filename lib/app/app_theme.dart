import 'package:flutter/material.dart';

class AppTheme {
  static const Color _seed = Color(0xFF1D4ED8);
  static const Color _ink = Color(0xFF0F172A);
  static const Color _inkMuted = Color(0xFF334155);
  static const Color _surface = Color(0xFFF8FAFC);

  static ThemeData get light {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: Brightness.light,
    ).copyWith(
      onSurface: _ink,
      onSurfaceVariant: _inkMuted,
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
        .apply(bodyColor: _ink, displayColor: _ink);

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: _surface,
      textTheme: textTheme,
      visualDensity: VisualDensity.comfortable,
      iconTheme: const IconThemeData(size: 28, color: _ink),
      primaryIconTheme: const IconThemeData(size: 28, color: _ink),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        toolbarHeight: 72,
        backgroundColor: _surface,
        foregroundColor: _ink,
        titleTextStyle: textTheme.headlineSmall,
        iconTheme: const IconThemeData(size: 32, color: _ink),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: colorScheme.outlineVariant),
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
        fillColor: Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
        hintStyle: const TextStyle(fontSize: 18, color: _inkMuted),
        labelStyle: const TextStyle(fontSize: 18),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: colorScheme.primary, width: 2),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 88,
        backgroundColor: Colors.white,
        indicatorColor: colorScheme.primaryContainer,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 15,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? colorScheme.primary : _inkMuted,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            size: 30,
            color: selected ? colorScheme.primary : _inkMuted,
          );
        }),
      ),
      sliderTheme: const SliderThemeData(
        trackHeight: 8,
      ),
    );
  }
}
