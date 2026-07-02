import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

import '../../profile/application/user_providers.dart'
    show userRepositoryProvider;
import '../data/places_autocomplete_service.dart';
import '../data/resolve_gym_place_service.dart';
import '../domain/gym_suggestion.dart';
import 'gym_providers.dart' show gymRepositoryProvider;

/// Bundle-restricted Places client key. Provided at build/run time via
/// `--dart-define=PLACES_CLIENT_KEY=<key>` — NEVER committed to the repo.
/// Empty by default; both [PlacesAutocompleteService.search] and
/// [ResolveGymPlaceService.call] surface a clear config error (not a crash)
/// when this is empty, e.g. in dev builds that forgot to pass the define.
///
/// Shared by BOTH Autocomplete AND Place Details resolution (Plan B pivot —
/// see [ResolveGymPlaceService] doc comment for why Details moved
/// client-side too, reusing the same bundle-restricted key instead of a
/// separate server-side key held in Secret Manager).
const String _placesClientKey =
    String.fromEnvironment('PLACES_CLIENT_KEY', defaultValue: '');

/// Shared `http.Client` for Places requests (Autocomplete + Details). A
/// single long-lived client (not `Provider.autoDispose`) matches the
/// codebase's other singleton-service providers.
final httpClientProvider = Provider<http.Client>((ref) => http.Client());

/// Provider for [PlacesAutocompleteService]. Overridable in tests.
final placesAutocompleteServiceProvider = Provider<PlacesAutocompleteService>(
  (ref) => PlacesAutocompleteService(
    httpClient: ref.watch(httpClientProvider),
    clientApiKey: _placesClientKey,
  ),
);

/// Provider for [ResolveGymPlaceService] — CLIENT-SIDE (Plan B pivot).
///
/// The original design called a `resolveGymPlace` Cloud Function (Admin SDK
/// + server-side key in Secret Manager, `functions/src/places-search.ts`).
/// That CF CANNOT be deployed: GCP project `treino-dev` sits under org
/// `code-assurance.com`, whose Domain-Restricted-Sharing policy blocks
/// public (`allUsers`) invoker on Cloud Functions. The CF is SHELVED
/// (kept, not exported from `functions/src/index.ts`) — resolution now
/// happens directly from the client via [ResolveGymPlaceService], reusing
/// [gymRepositoryProvider] for the read-through cache/upsert and the same
/// bundle-restricted [_placesClientKey] Autocomplete already uses.
final resolveGymPlaceServiceProvider = Provider<ResolveGymPlaceService>(
  (ref) => ResolveGymPlaceService(
    gymRepository: ref.watch(gymRepositoryProvider),
    httpClient: ref.watch(httpClientProvider),
    clientApiKey: _placesClientKey,
  ),
);

/// Current Google Places Autocomplete session token.
///
/// Per spec gym-places-search: one token spans every keystroke of a search
/// session and the eventual Details resolution, and a NEW token must be
/// generated after a selection completes (or the picker reopens) — never
/// reused across sessions. This provider generates a fresh token the first
/// time it's read; [selectGymActionProvider] invalidates it after a
/// successful selection so the next read mints a new one.
///
/// NOT autoDispose: the token must survive the `AsyncLoading` blips of
/// [placesSuggestionsProvider] rebuilding on every keystroke — an autoDispose
/// provider with no listeners between keystrokes would mint a new token per
/// character, breaking the "one token per session" contract.
final gymSearchSessionTokenProvider = Provider<String>(
  (ref) => ref.watch(placesAutocompleteServiceProvider).newSessionToken(),
);

/// Best-effort current position for Autocomplete location bias.
///
/// Per spec: bias when location permission is ALREADY granted, fall back to
/// an unbiased search otherwise — WITHOUT prompting or blocking. Uses
/// `checkPermission()` (never `requestPermission()`) so a search never
/// triggers a surprise OS permission dialog; the dedicated location-rationale
/// flow (`athleteLocationProvider`, coach discovery) owns prompting.
///
/// Returns `null` on denied/restricted/unavailable/any error — never throws,
/// per the spec's "without blocking or erroring the search" contract.
final gymSearchLocationBiasProvider = FutureProvider.autoDispose<Position?>(
  (ref) async {
    try {
      final permission = await Geolocator.checkPermission();
      final granted = permission == LocationPermission.always ||
          permission == LocationPermission.whileInUse;
      if (!granted) return null;
      return await Geolocator.getCurrentPosition();
    } catch (_) {
      return null;
    }
  },
);

/// Debounced-by-caller Autocomplete suggestions for [query].
///
/// `FutureProvider.autoDispose.family` keyed on the raw query string —
/// mirrors `searchUsersProvider` (feed/application/search_users_provider.dart):
/// debounce is the caller's responsibility (a `Timer` in the eventual search
/// widget, Slice 3), this provider stays pure and cacheable per keystroke.
///
/// Empty/blank query returns `[]` immediately without calling the service.
final placesSuggestionsProvider =
    FutureProvider.autoDispose.family<List<GymSuggestion>, String>(
  (ref, query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];

    final service = ref.watch(placesAutocompleteServiceProvider);
    final sessionToken = ref.watch(gymSearchSessionTokenProvider);
    final position = await ref.watch(gymSearchLocationBiasProvider.future);

    return service.search(
      query: trimmed,
      sessionToken: sessionToken,
      biasLatitude: position?.latitude,
      biasLongitude: position?.longitude,
    );
  },
);

/// `AsyncNotifier`-based select-gym action.
///
/// Resolves the selected [GymSuggestion.placeId] via `resolveGymPlace`
/// (server-side Details + `gyms/{placeId}` upsert), then updates
/// `users/{uid}` with the new `gymId` — `UserRepository.update` dual-writes
/// `gymName` from the now-existing `gyms/{gymId}` doc automatically (see
/// `_resolveGymName`, profile/data/user_repository.dart). Resets the search
/// session token on success so the NEXT search starts a new session (spec:
/// "A new search starts a new session token").
///
/// Exposes loading/error via the inherited `AsyncValue` state — no separate
/// error-handling plumbing needed by callers (Slice 3 UI reads
/// `selectGymActionProvider` directly).
class SelectGymAction extends AsyncNotifier<ResolveGymPlaceResult?> {
  @override
  ResolveGymPlaceResult? build() => null;

  Future<void> select({required String uid, required String placeId}) async {
    state = const AsyncLoading();
    final sessionToken = ref.read(gymSearchSessionTokenProvider);
    state = await AsyncValue.guard(() async {
      final result = await ref.read(resolveGymPlaceServiceProvider).call(
            placeId: placeId,
            sessionToken: sessionToken,
          );
      await ref
          .read(userRepositoryProvider)
          .update(uid, {'gymId': result.gymId});
      return result;
    });
    if (!state.hasError) {
      // Success — start a fresh session for the NEXT search (spec
      // requirement: never reuse a token across sessions).
      ref.invalidate(gymSearchSessionTokenProvider);
    }
  }
}

final selectGymActionProvider =
    AsyncNotifierProvider<SelectGymAction, ResolveGymPlaceResult?>(
  SelectGymAction.new,
);
