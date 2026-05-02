import 'package:flutter/material.dart';
import '../features/settings/presentation/controllers/theme_mode_controller.dart';

ThemeData buildTheme({
  required Brightness brightness,
  required AccentTheme accentTheme,
  ColorScheme? dynamicScheme,
}) {
  final scheme = accentTheme == AccentTheme.system && dynamicScheme != null
      ? dynamicScheme
      : ColorScheme.fromSeed(
          seedColor: _seedColorForAccent(accentTheme),
          brightness: brightness,
        );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surfaceContainerLow,
      foregroundColor: scheme.onSurface,
    ),
    cardTheme: CardThemeData(color: scheme.surfaceContainerLow),
    chipTheme: ChipThemeData(
      backgroundColor: scheme.surfaceContainer,
      selectedColor: scheme.primaryContainer,
      labelStyle: TextStyle(color: scheme.onSurface),
      secondaryLabelStyle: TextStyle(color: scheme.onPrimaryContainer),
      side: BorderSide(color: scheme.outlineVariant),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  );
}

Color _seedColorForAccent(AccentTheme accentTheme) {
  return switch (accentTheme) {
    AccentTheme.system => const Color(0xFFE9222A),
    AccentTheme.rtlDefault => const Color(0xFFE9222A),
    AccentTheme.blue => const Color(0xFF1565C0),
    AccentTheme.green => const Color(0xFF2E7D32),
    AccentTheme.purple => const Color(0xFF6A1B9A),
    AccentTheme.rose => const Color(0xFFC2185B),
    AccentTheme.orange => const Color(0xFFEF6C00),
  };
}
