import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

import '../../profile/application/user_providers.dart'
    show userRepositoryProvider;
import '../data/places_autocomplete_service.dart';
import '../data/places_nearby_search_service.dart';
import '../data/resolve_gym_place_service.dart';
import '../domain/gym_suggestion.dart';
import '../domain/nearby_gym.dart';
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

/// Provider for [PlacesNearbySearchService]. Mirrors
/// [placesAutocompleteServiceProvider] — same shared [httpClientProvider] +
/// bundle-restricted [_placesClientKey]. Overridable in tests (design AD-9
/// item 1).
final placesNearbySearchServiceProvider = Provider<PlacesNearbySearchService>(
  (ref) => PlacesNearbySearchService(
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

// ── Nearby gyms (searchNearby) — cost-gated, geohash-bucketed ─────────────
//
// searchNearby bills as Nearby Search Pro (~$32/1000, no free-session
// model), unlike Autocomplete. Cost gating is therefore STRUCTURAL and
// provider-owned (design gym-selection-v2 AD-2/AD-9) — never a
// widget-level "please don't rebuild too much" convention. Two layers:
//   1. Fire-once-per-open floor: `nearbyGymsProvider` is an
//      `autoDispose.family` keyed by a geohash5 bucket — Riverpod memoizes
//      the family entry for the life of the screen; rebuilds never re-fetch.
//   2. Cross-open TTL cache: results are stashed in `nearbyGymsCacheProvider`
//      (`keepAlive`), a `Map<geohashBucket, _CachedNearby>` with a 10-min
//      TTL. The family provider consults the cache FIRST; a hit within TTL
//      returns cached results with ZERO network call, even after the
//      `autoDispose` family entry was torn down and recreated (screen
//      closed/reopened within the same app session).

/// One cached `searchNearby` result set for a geohash5 bucket, with the
/// timestamp it was fetched at (for TTL expiry).
class _CachedNearby {
  const _CachedNearby(this.results, this.fetchedAt);

  final List<NearbyGym> results;
  final DateTime fetchedAt;
}

/// Cross-open cache TTL (design AD-2 layer 2). Gyms are near-static — 10
/// minutes bounds staleness while eliminating the most common repeat cost
/// (mis-tap / back-navigation / re-check re-opens of the same screen).
const Duration nearbyGymsCacheTtl = Duration(minutes: 10);

/// Tiny in-memory holder for the cross-open TTL cache (design AD-9 item 2).
///
/// Plain mutable class (not a `StateNotifier` — nothing external needs to
/// observe cache mutations; only `nearbyGymsProvider` reads/writes it) so
/// tests can construct one pre-seeded via [put] and override
/// [nearbyGymsCacheProvider] with it (see `NearbyGymsCache.new` +
/// `overrideWithValue` in provider tests).
class NearbyGymsCache {
  final Map<String, _CachedNearby> _entries = {};

  /// Returns the cached results for [bucket] if present AND fetched within
  /// [nearbyGymsCacheTtl] of [now]; otherwise `null` (miss — either never
  /// fetched, or expired).
  List<NearbyGym>? get(String bucket, {required DateTime now}) {
    final entry = _entries[bucket];
    if (entry == null) return null;
    if (now.difference(entry.fetchedAt) > nearbyGymsCacheTtl) return null;
    return entry.results;
  }

  /// Stores [results] for [bucket]. [fetchedAt] defaults to "now" — tests
  /// pass an explicit past timestamp to simulate an already-expired entry
  /// without a real 10-minute wait.
  void put(String bucket, List<NearbyGym> results, {DateTime? fetchedAt}) {
    _entries[bucket] = _CachedNearby(results, fetchedAt ?? DateTime.now());
  }
}

/// Provider for the cross-open TTL cache holder. `keepAlive` (the default
/// for a plain [Provider]) so it survives the `autoDispose` family entries
/// of [nearbyGymsProvider] being created/destroyed as the screen
/// opens/closes/reopens within one app session (design AD-9 item 2).
final nearbyGymsCacheProvider = Provider<NearbyGymsCache>(
  (ref) => NearbyGymsCache(),
);

/// Distance-ranked nearby gyms for a geohash5 [bucket], cost-gated per
/// design AD-2/AD-9.
///
/// `FutureProvider.autoDispose.family<List<NearbyGym>, String>` keyed by a
/// *screen-open-scoped location bucket* (`geohash5(lat, lng)`, ~4.9km cell —
/// almost exactly the fixed 5km search radius), NOT raw lat/lng: two
/// screen-opens in the same neighborhood resolve to the same key, which is
/// what makes the TTL cache below effective.
///
/// Consults [nearbyGymsCacheProvider] first — a hit within TTL returns
/// cached results with ZERO network call. On a miss, calls
/// [PlacesNearbySearchService.search] exactly once, stores the result in the
/// cache, and returns it. Riverpod memoizes this family entry for the
/// life of the screen, so rebuilds/re-renders never re-invoke this body —
/// the "fire-once-per-open" floor (AD-2 layer 1).
final nearbyGymsProvider =
    FutureProvider.autoDispose.family<List<NearbyGym>, String>(
  (ref, bucket) async {
    final cache = ref.watch(nearbyGymsCacheProvider);
    final cached = cache.get(bucket, now: DateTime.now());
    if (cached != null) return cached;

    final service = ref.watch(placesNearbySearchServiceProvider);
    final bucketLatLng = _decodeGeohashBucketCenter(bucket);
    final results = await service.search(
      latitude: bucketLatLng.$1,
      longitude: bucketLatLng.$2,
    );

    cache.put(bucket, results);
    return results;
  },
);

/// Decodes a geohash5 bucket string back into an approximate lat/lng center
/// — `searchNearby` needs real coordinates, not the bucket string itself.
/// Uses the same base32 alphabet as `geohash5` (core/utils/geohash.dart);
/// duplicated here as the inverse operation rather than adding a shared
/// decode function with only one caller.
(double, double) _decodeGeohashBucketCenter(String bucket) {
  const base32 = '0123456789bcdefghjkmnpqrstuvwxyz';
  double minLat = -90.0, maxLat = 90.0;
  double minLon = -180.0, maxLon = 180.0;
  var isLon = true;

  for (final char in bucket.toLowerCase().split('')) {
    final idx = base32.indexOf(char);
    if (idx == -1) continue;
    for (var bit = 4; bit >= 0; bit--) {
      final value = (idx >> bit) & 1;
      if (isLon) {
        final mid = (minLon + maxLon) / 2;
        if (value == 1) {
          minLon = mid;
        } else {
          maxLon = mid;
        }
      } else {
        final mid = (minLat + maxLat) / 2;
        if (value == 1) {
          minLat = mid;
        } else {
          maxLat = mid;
        }
      }
      isLon = !isLon;
    }
  }

  return ((minLat + maxLat) / 2, (minLon + maxLon) / 2);
}
