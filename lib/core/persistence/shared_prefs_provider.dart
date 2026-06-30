import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Resolves the [SharedPreferences] instance once at boot.
///
/// Promoted from `lib/features/coach_hub/application/sidebar_collapsed_provider.dart`
/// so it can be shared across features (ADR-LM-007). Eager-resolved in
/// `main.dart` before `runApp` and overridden with a `ProviderScope` override,
/// so `.requireValue` is always safe at provider init time (ADR-LM-009).
final sharedPreferencesProvider = FutureProvider<SharedPreferences>(
  (_) => SharedPreferences.getInstance(),
);
