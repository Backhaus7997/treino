import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/persistence/shared_prefs_provider.dart';

const _kThemeModeKey = 'app.theme_mode';

/// Manages and persists the user's [ThemeMode] choice.
///
/// Reads/writes the `app.theme_mode` key in [SharedPreferences] with string
/// values `'system' | 'light' | 'dark'`. Defaults to [ThemeMode.system] on
/// first run and falls back to [ThemeMode.system] for any unrecognised value
/// (REQ-LM-003, REQ-LM-004, ADR-LM-007, ADR-LM-009).
class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  ThemeModeNotifier(this._prefs)
      : super(_fromString(_prefs.getString(_kThemeModeKey)));

  final SharedPreferences _prefs;

  static ThemeMode _fromString(String? value) {
    switch (value) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  static String _toString(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.system:
        return 'system';
    }
  }

  /// Persists [mode] immediately and updates the reactive state.
  Future<void> setMode(ThemeMode mode) async {
    state = mode;
    await _prefs.setString(_kThemeModeKey, _toString(mode));
  }
}

/// Reactive [ThemeMode] provider backed by [SharedPreferences].
///
/// Depends on [sharedPreferencesProvider] being eagerly resolved before
/// `runApp` (ADR-LM-009), so `.requireValue` is always safe here.
final themeModeProvider =
    StateNotifierProvider<ThemeModeNotifier, ThemeMode>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider).requireValue;
  return ThemeModeNotifier(prefs);
});
