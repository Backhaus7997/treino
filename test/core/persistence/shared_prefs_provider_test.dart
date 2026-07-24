import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:treino/app/theme/theme_mode_provider.dart';
import 'package:treino/core/persistence/shared_prefs_provider.dart';

/// Boot contract of [sharedPreferencesOverride] (ADR-LM-009, #543).
///
/// The entry points eager-resolve [SharedPreferences] before `runApp` and feed
/// it in through this override. That only buys anything if the override is
/// **synchronous** — these tests pin the contract so nobody reintroduces the
/// `async` callback that shipped the first-frame StateError.
void main() {
  group('sharedPreferencesOverride', () {
    late SharedPreferences prefs;

    setUp(() async {
      SharedPreferences.setMockInitialValues({'app.theme_mode': 'dark'});
      prefs = await SharedPreferences.getInstance();
    });

    test('exposes AsyncData on the very first read, no await needed', () {
      final container = ProviderContainer(
        overrides: [sharedPreferencesOverride(prefs)],
      );
      addTearDown(container.dispose);

      // No await: this is exactly what the first frame does.
      final value = container.read(sharedPreferencesProvider);
      expect(value, isA<AsyncData<SharedPreferences>>());
      expect(value.requireValue, same(prefs));
    });

    test('requireValue consumers build on the first frame', () {
      final container = ProviderContainer(
        overrides: [sharedPreferencesOverride(prefs)],
      );
      addTearDown(container.dispose);

      // themeModeProvider calls `.requireValue`; before #543 this threw a
      // StateError while building TreinoApp.
      expect(container.read(themeModeProvider), ThemeMode.dark);
    });

    test('async override regresses to AsyncLoading on the first read', () {
      // Documents the bug shape sharedPreferencesOverride exists to prevent:
      // an `async` callback returns a Future, and even an already-completed
      // Future still needs a microtask — the first frame sees no value.
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWith((_) async => prefs),
        ],
      );
      addTearDown(container.dispose);

      expect(
        container.read(sharedPreferencesProvider),
        isA<AsyncLoading<SharedPreferences>>(),
      );
    });
  });
}
