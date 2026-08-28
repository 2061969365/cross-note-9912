import 'package:flutter/material.dart';

ThemeData buildTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(seedColor: const Color(0xFF4F6EF7), brightness: brightness);
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    appBarTheme: AppBarTheme(backgroundColor: scheme.surface, foregroundColor: scheme.onSurface),
    cardTheme: CardThemeData(color: scheme.surfaceContainerLow, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
  );
}
