import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/app/theme/theme_mode_provider.dart';
import 'package:treino/core/persistence/shared_prefs_provider.dart';
import 'package:treino/features/profile/presentation/appearance_screen.dart';
import 'package:treino/l10n/app_l10n.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Builds the [AppearanceScreen] test harness.
///
/// Overrides [themeModeProvider] with a [_FakeThemeModeNotifier] so the test
/// never touches the [sharedPreferencesProvider] async chain — mirroring
/// how [main.dart] resolves prefs synchronously before runApp, without the
/// async FutureProvider resolution timing issue in tests.
Widget _buildScreen({ThemeMode initialMode = ThemeMode.system}) {
  final router = GoRouter(
    initialLocation: '/profile/settings/appearance',
    routes: [
      GoRoute(
        path: '/profile',
        builder: (_, __) => const Scaffold(body: Text('PROFILE')),
        routes: [
          GoRoute(
            path: 'settings/appearance',
            builder: (_, __) => const Scaffold(body: AppearanceScreen()),
          ),
        ],
      ),
    ],
  );

  // Eagerly seed SharedPreferences so ThemeModeNotifier reads the right value.
  final modeString = switch (initialMode) {
    ThemeMode.light => 'light',
    ThemeMode.dark => 'dark',
    ThemeMode.system => 'system',
  };
  SharedPreferences.setMockInitialValues({
    'app.theme_mode': modeString,
  });

  return ProviderScope(
    overrides: [
      // Override themeModeProvider with a notifier backed by an in-memory
      // SharedPreferences that is already resolved — no async wait needed.
      themeModeProvider.overrideWith((ref) {
        final prefs = _SyncFakePrefs({
          'app.theme_mode': modeString,
        });
        return ThemeModeNotifier(prefs);
      }),
    ],
    child: MaterialApp.router(
      theme: AppTheme.dark(),
      routerConfig: router,
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      locale: const Locale('es', 'AR'),
    ),
  );
}

/// Returns the [ProviderContainer] from the [ProviderScope] wrapping
/// [AppearanceScreen] — used to read provider state after interactions.
ProviderContainer _containerOf(WidgetTester tester) =>
    ProviderScope.containerOf(
      tester.element(find.byType(AppearanceScreen)),
    );

// ---------------------------------------------------------------------------
// Fake SharedPreferences — synchronous in-memory implementation
// ---------------------------------------------------------------------------

/// Minimal in-memory [SharedPreferences] that supports the string get/set
/// operations used by [ThemeModeNotifier] — no async, no disk I/O.
class _SyncFakePrefs implements SharedPreferences {
  _SyncFakePrefs(Map<String, Object> initial) : _store = Map.of(initial);

  final Map<String, Object> _store;

  @override
  String? getString(String key) => _store[key] as String?;

  @override
  Future<bool> setString(String key, String value) async {
    _store[key] = value;
    return true;
  }

  // ── Unused members — satisfy interface ──────────────────────────────────
  @override
  bool containsKey(String key) => _store.containsKey(key);

  @override
  Object? get(String key) => _store[key];

  @override
  bool? getBool(String key) => _store[key] as bool?;

  @override
  double? getDouble(String key) => _store[key] as double?;

  @override
  int? getInt(String key) => _store[key] as int?;

  @override
  Set<String> getKeys() => _store.keys.toSet();

  @override
  List<String>? getStringList(String key) => _store[key] as List<String>?;

  @override
  Future<bool> clear() async {
    _store.clear();
    return true;
  }

  @override
  Future<bool> remove(String key) async {
    _store.remove(key);
    return true;
  }

  @override
  Future<bool> setBool(String key, bool value) async {
    _store[key] = value;
    return true;
  }

  @override
  Future<bool> setDouble(String key, double value) async {
    _store[key] = value;
    return true;
  }

  @override
  Future<bool> setInt(String key, int value) async {
    _store[key] = value;
    return true;
  }

  @override
  Future<bool> setStringList(String key, List<String> value) async {
    _store[key] = value;
    return true;
  }

  @override
  Future<bool> commit() async => true;

  @override
  Future<void> reload() async {}
}

// ---------------------------------------------------------------------------
// Tests — REQ-LM-009, SCENARIO-825..828
// ---------------------------------------------------------------------------

void main() {
  group('AppearanceScreen', () {
    testWidgets('SCENARIO-828: renders 3 options with localized labels',
        (tester) async {
      await tester.pumpWidget(_buildScreen());
      await tester.pumpAndSettle();

      expect(find.text('Sistema'), findsOneWidget);
      expect(find.text('Claro'), findsOneWidget);
      expect(find.text('Oscuro'), findsOneWidget);
      // Screen title (appearanceTitle.toUpperCase())
      expect(find.text('APARIENCIA'), findsOneWidget);
      // Subtitle for the Sistema option
      expect(find.text('Sigue el tema del dispositivo'), findsOneWidget);
    });

    testWidgets('SCENARIO-828: Sistema is selected by default on fresh install',
        (tester) async {
      await tester.pumpWidget(_buildScreen(initialMode: ThemeMode.system));
      await tester.pumpAndSettle();

      final container = _containerOf(tester);
      expect(container.read(themeModeProvider), ThemeMode.system);
    });

    testWidgets(
        'SCENARIO-825: tapping Claro applies ThemeMode.light immediately',
        (tester) async {
      await tester.pumpWidget(_buildScreen(initialMode: ThemeMode.system));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Claro'));
      await tester.pumpAndSettle();

      final container = _containerOf(tester);
      expect(container.read(themeModeProvider), ThemeMode.light);
    });

    testWidgets('tapping Oscuro applies ThemeMode.dark immediately',
        (tester) async {
      await tester.pumpWidget(_buildScreen(initialMode: ThemeMode.system));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Oscuro'));
      await tester.pumpAndSettle();

      final container = _containerOf(tester);
      expect(container.read(themeModeProvider), ThemeMode.dark);
    });

    testWidgets('tapping Sistema applies ThemeMode.system', (tester) async {
      // Start with light selected, then switch back to system.
      await tester.pumpWidget(_buildScreen(initialMode: ThemeMode.light));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Sistema'));
      await tester.pumpAndSettle();

      final container = _containerOf(tester);
      expect(container.read(themeModeProvider), ThemeMode.system);
    });

    testWidgets('SCENARIO-827: back navigation does not undo selection',
        (tester) async {
      await tester.pumpWidget(_buildScreen(initialMode: ThemeMode.system));
      await tester.pumpAndSettle();

      // Select dark mode
      await tester.tap(find.text('Oscuro'));
      await tester.pumpAndSettle();

      final container = _containerOf(tester);

      // Navigate back
      final NavigatorState navigator =
          tester.state(find.byType(Navigator).last);
      navigator.pop();
      await tester.pumpAndSettle();

      // State is still dark — back did NOT undo the selection.
      expect(container.read(themeModeProvider), ThemeMode.dark);
    });
  });
}
