import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Resolves the [SharedPreferences] instance once at boot.
///
/// Promoted from `lib/features/coach_hub/application/sidebar_collapsed_provider.dart`
/// so it can be shared across features (ADR-LM-007). Eager-resolved in
/// `main.dart` before `runApp` and overridden with a `ProviderScope` override,
/// so `.requireValue` is always safe at provider init time (ADR-LM-009).
///
/// Entry points must feed the resolved instance in through
/// [sharedPreferencesOverride] rather than building the override inline.
final sharedPreferencesProvider = FutureProvider<SharedPreferences>(
  (_) => SharedPreferences.getInstance(),
);

/// Boot-time override that hands the already-resolved [prefs] to
/// [sharedPreferencesProvider]. Shared by `main.dart` and `main_coach_hub.dart`.
///
/// The callback is deliberately **synchronous**. A `FutureProvider` only emits
/// [AsyncData] on the first synchronous read when its `create` returns a plain
/// `T`; an `async` callback returns a `Future` — even an already-completed one
/// still costs a microtask — which leaves the provider in [AsyncLoading] for
/// the first frame and makes every `.requireValue` consumer throw a
/// `StateError` while building the app (#543). That defeats the whole point of
/// eager-resolving before `runApp`. Do not add `async` here.
Override sharedPreferencesOverride(SharedPreferences prefs) =>
    sharedPreferencesProvider.overrideWith((_) => prefs);
