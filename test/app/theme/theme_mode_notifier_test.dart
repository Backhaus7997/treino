import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:treino/app/theme/theme_mode_provider.dart';
import 'package:treino/core/persistence/shared_prefs_provider.dart';

/// Builds a [ProviderContainer] with [SharedPreferences] pre-seeded with
/// [initialValues]. The container is automatically disposed after the test.
ProviderContainer _makeContainer(Map<String, Object> initialValues) {
  SharedPreferences.setMockInitialValues(initialValues);
  final prefs = SharedPreferences.getInstance();

  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWith((_) => prefs),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('ThemeModeNotifier', () {
    test('defaults to ThemeMode.system when no prefs entry exists', () async {
      final container = _makeContainer({});
      // Trigger resolution of sharedPreferencesProvider
      await container.read(sharedPreferencesProvider.future);

      final mode = container.read(themeModeProvider);
      expect(mode, ThemeMode.system);
    });

    test('reads persisted "light" value on init', () async {
      final container = _makeContainer({'app.theme_mode': 'light'});
      await container.read(sharedPreferencesProvider.future);

      final mode = container.read(themeModeProvider);
      expect(mode, ThemeMode.light);
    });

    test('reads persisted "dark" value on init', () async {
      final container = _makeContainer({'app.theme_mode': 'dark'});
      await container.read(sharedPreferencesProvider.future);

      final mode = container.read(themeModeProvider);
      expect(mode, ThemeMode.dark);
    });

    test('reads persisted "system" value on init', () async {
      final container = _makeContainer({'app.theme_mode': 'system'});
      await container.read(sharedPreferencesProvider.future);

      final mode = container.read(themeModeProvider);
      expect(mode, ThemeMode.system);
    });

    test('corrupted value falls back to ThemeMode.system', () async {
      final container = _makeContainer({'app.theme_mode': 'invalid_value'});
      await container.read(sharedPreferencesProvider.future);

      final mode = container.read(themeModeProvider);
      expect(mode, ThemeMode.system);
    });

    test('setMode(light) persists and updates state', () async {
      final container = _makeContainer({});
      await container.read(sharedPreferencesProvider.future);

      final notifier = container.read(themeModeProvider.notifier);
      await notifier.setMode(ThemeMode.light);

      expect(container.read(themeModeProvider), ThemeMode.light);

      // Verify it was actually written to SharedPreferences
      final prefs = await container.read(sharedPreferencesProvider.future);
      expect(prefs.getString('app.theme_mode'), 'light');
    });

    test('setMode(dark) persists and updates state', () async {
      final container = _makeContainer({});
      await container.read(sharedPreferencesProvider.future);

      final notifier = container.read(themeModeProvider.notifier);
      await notifier.setMode(ThemeMode.dark);

      expect(container.read(themeModeProvider), ThemeMode.dark);

      final prefs = await container.read(sharedPreferencesProvider.future);
      expect(prefs.getString('app.theme_mode'), 'dark');
    });

    test('setMode(system) persists and updates state', () async {
      final container = _makeContainer({'app.theme_mode': 'dark'});
      await container.read(sharedPreferencesProvider.future);

      final notifier = container.read(themeModeProvider.notifier);
      await notifier.setMode(ThemeMode.system);

      expect(container.read(themeModeProvider), ThemeMode.system);

      final prefs = await container.read(sharedPreferencesProvider.future);
      expect(prefs.getString('app.theme_mode'), 'system');
    });

    test('reload from prefs returns last persisted value', () async {
      // Simulate a full round-trip: write via first container, read via second.
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('app.theme_mode', 'dark');

      // New container reads from the now-mutated mock
      final container2 = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWith((_) async => prefs),
        ],
      );
      addTearDown(container2.dispose);

      await container2.read(sharedPreferencesProvider.future);
      expect(container2.read(themeModeProvider), ThemeMode.dark);
    });
  });
}
