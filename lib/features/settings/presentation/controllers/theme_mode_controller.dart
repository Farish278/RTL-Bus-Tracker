import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AccentTheme { system, rtlDefault, blue, green, purple, rose, orange }

/// How much route information the map UI shows.
/// [minimal] shows route numbers only; [informative] adds origin/destination
/// so riders unfamiliar with route numbers can still find their bus.
enum UiDetailLevel { minimal, informative }

class ThemeSettings {
  const ThemeSettings({
    this.mode = ThemeMode.system,
    this.accent = AccentTheme.rtlDefault,
    this.detailLevel = UiDetailLevel.informative,
  });

  final ThemeMode mode;
  final AccentTheme accent;
  final UiDetailLevel detailLevel;

  ThemeSettings copyWith({
    ThemeMode? mode,
    AccentTheme? accent,
    UiDetailLevel? detailLevel,
  }) {
    return ThemeSettings(
      mode: mode ?? this.mode,
      accent: accent ?? this.accent,
      detailLevel: detailLevel ?? this.detailLevel,
    );
  }
}

class ThemeModeController extends StateNotifier<ThemeSettings> {
  ThemeModeController() : super(const ThemeSettings()) {
    _load();
  }

  static const _kThemeMode = 'theme_mode';
  static const _kAccentTheme = 'accent_theme';
  static const _kDetailLevel = 'ui_detail_level';

  Future<void> setDetailLevel(UiDetailLevel level) async {
    state = state.copyWith(detailLevel: level);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kDetailLevel, level.name);
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final modeValue = prefs.getString(_kThemeMode);
    final accentValue = prefs.getString(_kAccentTheme);
    final detailLevel = prefs.getString(_kDetailLevel) == 'minimal'
        ? UiDetailLevel.minimal
        : UiDetailLevel.informative;

    final mode = switch (modeValue) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };

    final accent = switch (accentValue) {
      'system' => AccentTheme.system,
      'blue' => AccentTheme.blue,
      'green' => AccentTheme.green,
      'purple' => AccentTheme.purple,
      'rose' => AccentTheme.rose,
      'orange' => AccentTheme.orange,
      _ => AccentTheme.rtlDefault,
    };

    state = ThemeSettings(mode: mode, accent: accent, detailLevel: detailLevel);
  }

  Future<void> setMode(ThemeMode mode) async {
    state = state.copyWith(mode: mode);
    final prefs = await SharedPreferences.getInstance();
    final value = switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    };
    await prefs.setString(_kThemeMode, value);
  }

  Future<void> setAccent(AccentTheme accent) async {
    state = state.copyWith(accent: accent);
    final prefs = await SharedPreferences.getInstance();
    final value = switch (accent) {
      AccentTheme.system => 'system',
      AccentTheme.rtlDefault => 'rtl_default',
      AccentTheme.blue => 'blue',
      AccentTheme.green => 'green',
      AccentTheme.purple => 'purple',
      AccentTheme.rose => 'rose',
      AccentTheme.orange => 'orange',
    };
    await prefs.setString(_kAccentTheme, value);
  }
}

final themeSettingsProvider =
    StateNotifierProvider<ThemeModeController, ThemeSettings>((ref) {
      return ThemeModeController();
    });

final themeModeProvider = Provider<ThemeMode>((ref) {
  return ref.watch(themeSettingsProvider).mode;
});

final accentThemeProvider = Provider<AccentTheme>((ref) {
  return ref.watch(themeSettingsProvider).accent;
});

final uiDetailLevelProvider = Provider<UiDetailLevel>((ref) {
  return ref.watch(themeSettingsProvider).detailLevel;
});
