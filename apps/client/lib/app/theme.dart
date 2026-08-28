import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

abstract class AppRadius {
  static const double sm = 10;
  static const double md = 14;
  static const double lg = 20;
  static const double xl = 28;
  static const double pill = 999;
}

abstract class AppSpace {
  static const double xs = 6;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 28;
}

const _seed = Color(0xFF4E5EEA);
const _darkSurface = Color(0xFF101114);

ThemeData buildTheme(Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: _seed,
    brightness: brightness,
    surface: isDark ? _darkSurface : null,
  );

  final baseText = (isDark ? ThemeData.dark() : ThemeData.light()).textTheme;
  final outfit = GoogleFonts.outfitTextTheme(baseText);
  final inter = GoogleFonts.interTextTheme(baseText);

  TextTheme text = baseText.copyWith(
    displayLarge: outfit.displayLarge?.copyWith(
      fontWeight: FontWeight.w600, letterSpacing: -0.8, height: 1.05),
    headlineMedium: outfit.headlineMedium?.copyWith(
      fontWeight: FontWeight.w600, letterSpacing: -0.6, height: 1.1),
    titleLarge: outfit.titleLarge?.copyWith(
      fontWeight: FontWeight.w600, letterSpacing: -0.3, height: 1.2),
    titleMedium: outfit.titleMedium?.copyWith(
      fontWeight: FontWeight.w600, letterSpacing: -0.2),
    bodyLarge: inter.bodyLarge?.copyWith(height: 1.55),
    bodyMedium: inter.bodyMedium?.copyWith(height: 1.55),
    labelSmall: inter.labelSmall?.copyWith(
      fontWeight: FontWeight.w600, letterSpacing: 0.6, fontFeatures: const [FontFeature.tabularFigures()]),
    labelLarge: inter.labelLarge?.copyWith(fontWeight: FontWeight.w600),
  );

  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    scaffoldBackgroundColor: isDark ? _darkSurface : scheme.surface,
    textTheme: text,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      elevation: 0,
      titleTextStyle: text.titleLarge?.copyWith(color: scheme.onSurface),
    ),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant.withValues(alpha: 0.6), space: 1, thickness: 1),
    cardTheme: CardThemeData(
      color: isDark ? scheme.surfaceContainerLow : scheme.surfaceContainerLowest,
      elevation: 0,
      shadowColor: _seed.withValues(alpha: 0.12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
      margin: EdgeInsets.zero,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: isDark ? scheme.surfaceContainerHigh.withValues(alpha: 0.6) : scheme.surfaceContainerHigh.withValues(alpha: 0.55),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.md), borderSide: BorderSide(color: scheme.outlineVariant)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.md), borderSide: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.8))),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.md), borderSide: BorderSide(color: scheme.primary, width: 1.4)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      hintStyle: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant.withValues(alpha: 0.7)),
      isDense: true,
    ),
    chipTheme: ChipThemeData(
      backgroundColor: scheme.surfaceContainerHigh,
      selectedColor: scheme.primaryContainer,
      labelStyle: text.labelLarge?.copyWith(fontSize: 13),
      secondaryLabelStyle: text.labelLarge?.copyWith(fontSize: 13, color: scheme.onPrimaryContainer),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.pill)),
      side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surface,
      indicatorColor: scheme.primaryContainer,
      height: 72,
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final sel = states.contains(WidgetState.selected);
        return text.labelSmall?.copyWith(
          fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
          color: sel ? scheme.onSurface : scheme.onSurfaceVariant,
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        final sel = states.contains(WidgetState.selected);
        return IconThemeData(color: sel ? scheme.onPrimaryContainer : scheme.onSurfaceVariant, size: 22);
      }),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        textStyle: text.labelLarge,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
        side: BorderSide(color: scheme.outlineVariant),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        textStyle: text.labelLarge,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
        textStyle: text.labelLarge,
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: scheme.primary,
      foregroundColor: scheme.onPrimary,
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.xl)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: scheme.inverseSurface,
      contentTextStyle: text.bodyMedium?.copyWith(color: scheme.onInverseSurface),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
    ),
  );
}
