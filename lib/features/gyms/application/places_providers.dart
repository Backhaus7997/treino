import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

import '../../../core/utils/geohash.dart';
import '../../profile/application/user_providers.dart'
    show userRepositoryProvider;
import '../data/places_nearby_search_service.dart';
import '../data/places_text_search_service.dart';
import '../data/resolve_gym_place_service.dart';
import '../domain/gym_suggestion.dart';
import '../domain/nearby_gym.dart';
import 'gym_providers.dart' show gymRepositoryProvider;

/// Bundle-restricted Places client key. Provided at build/run time via
/// `--dart-define=PLACES_CLIENT_KEY=<key>` — NEVER committed to the repo.
/// Empty by default; both [PlacesTextSearchService.search] and
/// [ResolveGymPlaceService.call] surface a clear config error (not a crash)
/// when this is empty, e.g. in dev builds that forgot to pass the define.
///
/// Shared by BOTH Text Search AND Place Details resolution (Plan B pivot —
/// see [ResolveGymPlaceService] doc comment for why Details moved
/// client-side too, reusing the same bundle-restricted key instead of a
/// separate server-side key held in Secret Manager).
const String _placesClientKey =
    String.fromEnvironment('PLACES_CLIENT_KEY', defaultValue: '');

/// Shared `http.Client` for Places requests (Text Search + Details). A
/// single long-lived client (not `Provider.autoDispose`) matches the
/// codebase's other singleton-service providers.
final httpClientProvider = Provider<http.Client>((ref) => http.Client());

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
/// bundle-restricted [_placesClientKey] Text Search already uses.
final resolveGymPlaceServiceProvider = Provider<ResolveGymPlaceService>(
  (ref) => ResolveGymPlaceService(
    gymRepository: ref.watch(gymRepositoryProvider),
    httpClient: ref.watch(httpClientProvider),
    clientApiKey: _placesClientKey,
  ),
);

/// Provider for [PlacesNearbySearchService]. Mirrors
/// [placesTextSearchServiceProvider] — same shared [httpClientProvider] +
/// bundle-restricted [_placesClientKey]. Overridable in tests (design AD-9
/// item 1).
final placesNearbySearchServiceProvider = Provider<PlacesNearbySearchService>(
  (ref) => PlacesNearbySearchService(
    httpClient: ref.watch(httpClientProvider),
    clientApiKey: _placesClientKey,
  ),
);

/// Provider for [PlacesTextSearchService]. Mirrors
/// [placesNearbySearchServiceProvider] — same shared [httpClientProvider] +
/// bundle-restricted [_placesClientKey]. Overridable in tests (design AD-12).
final placesTextSearchServiceProvider = Provider<PlacesTextSearchService>(
  (ref) => PlacesTextSearchService(
    httpClient: ref.watch(httpClientProvider),
    clientApiKey: _placesClientKey,
  ),
);

/// Best-effort current position for typed-search location bias.
///
/// Per spec: bias when location permission is ALREADY granted, fall back to
/// an unbiased search otherwise — WITHOUT prompting or blocking. Uses
/// `checkPermission()` (never `requestPermission()`) so a search never
/// triggers a surprise OS permission dialog; the dedicated location-rationale
/// flow (`athleteLocationProvider`, coach discovery) owns prompting.
///
/// Returns `null` on denied/restricted/unavailable/any error — never throws,
/// per the spec's "without blocking or erroring the search" contract. Feeds
/// [placesTextSearchProvider]'s `locationBias` the same way it fed
/// Autocomplete's `locationBias` before the Phase 3 backend swap (AD-12) —
/// this provider itself is UNCHANGED by that swap.
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

/// `AsyncNotifier`-based select-gym action.
///
/// Resolves the selected [GymSuggestion.placeId] via `resolveGymPlace`
/// (server-side Details + `gyms/{placeId}` upsert), then updates
/// `users/{uid}` with the new `gymId` — `UserRepository.update` dual-writes
/// `gymName` from the now-existing `gyms/{gymId}` doc automatically (see
/// `_resolveGymName`, profile/data/user_repository.dart).
///
/// Exposes loading/error via the inherited `AsyncValue` state — no separate
/// error-handling plumbing needed by callers.
class SelectGymAction extends AsyncNotifier<ResolveGymPlaceResult?> {
  @override
  ResolveGymPlaceResult? build() => null;

  /// Resolves [placeId] and persists it as the athlete's `gymId`.
  ///
  /// [useSessionToken] is a legacy parameter from the retired
  /// Autocomplete-session era (spec gym-places-search "A nearby-originated
  /// selection resolves without a session token"). Per design AD-12, Text
  /// Search has no session concept either — EVERY caller (typed search AND
  /// nearby list) now passes `useSessionToken: false`, so [sessionToken] is
  /// always `null` in practice. The parameter is kept (rather than removed
  /// outright) because [ResolveGymPlaceService.call] still accepts an
  /// optional token, and a future session-backed source is not
  /// architecturally precluded.
  Future<void> select({
    required String uid,
    required String placeId,
    bool useSessionToken = false,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final result = await ref.read(resolveGymPlaceServiceProvider).call(
            placeId: placeId,
            sessionToken: null,
          );
      await ref
          .read(userRepositoryProvider)
          .update(uid, {'gymId': result.gymId});
      return result;
    });
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

// ── nearbyLocationProvider — HYBRID location pattern (AD-1/AD-9 item 4) ────

/// States for the nearby-list location flow:
///   - `AsyncData(null)`   = initial / not-yet-checked / denied / skipped
///   - `AsyncLoading`      = escalation in flight (rationale accepted,
///                           `requestPermission()` + GPS acquisition running)
///   - `AsyncData(pos)`    = granted and a `Position` is available
///   - `AsyncError`        = hardware/service error during escalation
///
/// Structurally mirrors `AthleteLocationNotifier`
/// (coach/application/trainer_discovery_providers.dart) but adds a silent
/// [checkSilently] step: per design AD-1 (HYBRID), the nearby-gyms screen
/// runs a silent `Geolocator.checkPermission()` on screen-open (NEVER
/// `requestPermission()` — that would surprise the user with an OS dialog
/// they didn't ask for). Only when the UI-driven [requestPermission]
/// escalation runs (after the user taps the inline "Activar ubicación"
/// affordance AND accepts the rationale sheet) does a real permission
/// prompt fire.
///
/// `build()` itself performs NO Geolocator call — it starts at the same
/// neutral `AsyncData(null)` as `AthleteLocationNotifier`. The UI is
/// responsible for calling [checkSilently] once on screen-open. This keeps
/// simply *constructing/reading* the provider safe under `test()` AND
/// `testWidgets()` (never touches the plugin channel), while still letting
/// production code run the silent check the design calls for.
class NearbyLocationNotifier extends StateNotifier<AsyncValue<Position?>> {
  NearbyLocationNotifier() : super(const AsyncData(null));

  bool _isPermissionDenied = false;

  /// Whether the last permission check/escalation resulted in a denied
  /// state. The UI reads this to decide whether to show the inline
  /// "Activar ubicación" affordance.
  bool get isPermissionDenied => _isPermissionDenied;

  /// Silent permission check — uses `checkPermission()` (NEVER
  /// `requestPermission()`), so calling this never triggers a surprise OS
  /// dialog. Call once per screen-open. On denied/restricted/unavailable/
  /// any error, resolves to the not-granted state — never throws.
  Future<void> checkSilently() async {
    try {
      final permission = await Geolocator.checkPermission();
      final granted = permission == LocationPermission.always ||
          permission == LocationPermission.whileInUse;
      if (!granted) {
        _isPermissionDenied = true;
        state = const AsyncData(null);
        return;
      }
      _isPermissionDenied = false;
      state = AsyncData(await Geolocator.getCurrentPosition());
    } catch (_) {
      _isPermissionDenied = true;
      state = const AsyncData(null);
    }
  }

  /// Escalation: requests OS permission then acquires position. Call this
  /// ONLY after the explicit rationale sheet
  /// (`showLocationPermissionRationaleSheet`) was accepted by the user —
  /// NEVER on screen-open (AD-1).
  Future<void> requestPermission() async {
    state = const AsyncLoading();
    _isPermissionDenied = false;
    try {
      final permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _isPermissionDenied = true;
        state = const AsyncData(null);
        return;
      }
      final pos = await Geolocator.getCurrentPosition();
      state = AsyncData(pos);
    } catch (e, st) {
      state = AsyncError(e, st);
    }
  }

  // ── Test seams ────────────────────────────────────────────────────────
  //
  // `Geolocator.checkPermission()` HANGS FOREVER under `testWidgets` (see
  // test/features/profile_setup/presentation/gym_search_box_test.dart:264-305).
  // ALL tests MUST override this provider and drive state exclusively via
  // these seams — never let checkSilently()/requestPermission() run for
  // real in a test.

  /// Directly set a [Position] (for test overrides — never call in
  /// production).
  void setForTest(Position? pos) {
    _isPermissionDenied = false;
    state = AsyncData(pos);
  }

  /// Set denied state (for test overrides).
  void setDeniedForTest() {
    _isPermissionDenied = true;
    state = const AsyncData(null);
  }
}

/// Provider for the athlete's location as resolved for the nearby-gyms list
/// (design AD-1/AD-9 item 4). NOT autoDispose — mirrors
/// `athleteLocationProvider`'s scoping so the resolved position survives
/// widget rebuilds within a screen-open.
final nearbyLocationProvider =
    StateNotifierProvider<NearbyLocationNotifier, AsyncValue<Position?>>(
  (ref) => NearbyLocationNotifier(),
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

// ── Typed search (searchText) — cost-gated, debounced, cache-first ────────
//
// Text Search bills as Text Search Pro (~$32/1000, no free-session model),
// the same tier as searchNearby — unlike the retired Autocomplete's
// free/Essentials sessions. Cost gating is therefore STRUCTURAL and
// provider-owned (design gym-selection-v2 AD-12), verifiable by a
// call-counting fake service — never a widget-level convention. Mirrors the
// nearby-gyms cost-gating shape above (fire-once-settled-query + TTL cache),
// adapted for typed search's extra debounce/min-chars gates:
//   1. Debounce: `placesTextSearchProvider` waits
//      [textSearchDebounceDurationProvider] after being read before it
//      actually calls the service; if a NEWER family entry (a later
//      keystroke's query) takes over before the wait elapses, this entry is
//      disposed and never fires (`ref.mounted` guard).
//   2. Minimum 3 characters: shorter (trimmed) queries return `[]`
//      immediately, never reaching the debounce/network step.
//   3. Cache: settled results are stashed in [textSearchCacheProvider]
//      (`keepAlive`), keyed by `normalizedQuery|biasBucket` (biasBucket is
//      the empty string when no location is available), with a TTL. A hit
//      within TTL returns cached results with ZERO network call.

/// One cached `searchText` result set for a `query|biasBucket` cache key,
/// with the timestamp it was fetched at (for TTL expiry). Mirrors
/// `_CachedNearby`.
class _CachedTextSearch {
  const _CachedTextSearch(this.results, this.fetchedAt);

  final List<GymSuggestion> results;
  final DateTime fetchedAt;
}

/// Cross-open cache TTL (design AD-12) — mirrors [nearbyGymsCacheTtl].
const Duration textSearchCacheTtl = Duration(minutes: 10);

/// Debounce window (design AD-12): typed search waits this long after the
/// LAST read of a given query before actually calling the service. Widened
/// from the retired Autocomplete widget's 300ms `Timer` — a cost-bearing
/// backend with no free tier warrants a wider settle window. Overridable in
/// tests (`textSearchDebounceDurationProvider.overrideWithValue(...)`) so
/// tests never sleep the real 600ms.
const Duration defaultTextSearchDebounceDuration = Duration(milliseconds: 600);

/// Provider for the debounce duration — a plain value provider so tests can
/// override it to a near-zero duration without touching the debounce LOGIC
/// itself (design's "inject the debounce duration... so tests don't sleep").
final textSearchDebounceDurationProvider = Provider<Duration>(
  (ref) => defaultTextSearchDebounceDuration,
);

/// Minimum (trimmed) query length before a `searchText` request is ever
/// considered (design AD-12) — shorter queries rarely narrow to a useful
/// result set and would materially increase billed-call volume.
const int textSearchMinQueryLength = 3;

/// Tiny in-memory holder for the cache (design AD-12). Mirrors
/// [NearbyGymsCache]'s shape exactly (`get(key, {now})`/`put(key, results,
/// {fetchedAt})`), keyed here by a `String` cache key instead of a geohash
/// bucket.
class TextSearchCache {
  final Map<String, _CachedTextSearch> _entries = {};

  /// Returns the cached results for [key] if present AND fetched within
  /// [textSearchCacheTtl] of [now]; otherwise `null` (miss).
  List<GymSuggestion>? get(String key, {required DateTime now}) {
    final entry = _entries[key];
    if (entry == null) return null;
    if (now.difference(entry.fetchedAt) > textSearchCacheTtl) return null;
    return entry.results;
  }

  /// Stores [results] for [key]. [fetchedAt] defaults to "now" — tests pass
  /// an explicit past timestamp to simulate an already-expired entry.
  void put(String key, List<GymSuggestion> results, {DateTime? fetchedAt}) {
    _entries[key] = _CachedTextSearch(results, fetchedAt ?? DateTime.now());
  }
}

/// Provider for the cache holder. `keepAlive` (default for a plain
/// [Provider]) so it survives the `autoDispose` family entries of
/// [placesTextSearchProvider] being created/destroyed across queries/screen
/// opens within one app session (design AD-12).
final textSearchCacheProvider = Provider<TextSearchCache>(
  (ref) => TextSearchCache(),
);

/// Builds the cache key for [query] + the current location-bias bucket:
/// `normalizedQuery|biasBucket` (empty bucket segment when no location is
/// available) — two different bias buckets for the same query text are
/// treated as distinct cache entries, matching `searchText`'s bias-sensitive
/// ranking.
String _textSearchCacheKey(String normalizedQuery, Position? position) {
  final bucket =
      position == null ? '' : geohash5(position.latitude, position.longitude);
  return '$normalizedQuery|$bucket';
}

/// Debounced, cost-gated, cache-first typed-search results for [query]
/// (design AD-12). Replaces the retired `placesSuggestionsProvider`
/// (Autocomplete-backed) as `GymSearchBox`'s typed-search data source.
///
/// `FutureProvider.autoDispose.family<List<GymSuggestion>, String>` keyed on
/// the RAW per-keystroke query string — the WIDGET no longer owns a debounce
/// `Timer` (design AD-12/task 3.8); every keystroke reads this family with
/// its own query, and THIS provider is what gates the actual network call:
///   1. Trimmed query under [textSearchMinQueryLength] → `[]`, no network,
///      no debounce wait.
///   2. Otherwise, wait [textSearchDebounceDurationProvider]. If THIS family
///      entry is disposed before the wait elapses (a newer keystroke's
///      entry superseded it — Riverpod tears down the old `autoDispose`
///      entry once nothing depends on it), `ref.mounted` is `false` and the
///      body returns early WITHOUT calling the service.
///   3. After the wait, consult [textSearchCacheProvider] first — a hit
///      within TTL returns cached results with ZERO network call. On a
///      miss, call [PlacesTextSearchService.search] exactly once, cache the
///      result, and return it.
final placesTextSearchProvider =
    FutureProvider.autoDispose.family<List<GymSuggestion>, String>(
  (ref, query) async {
    final trimmed = query.trim();
    if (trimmed.length < textSearchMinQueryLength) return const [];

    // `ref.mounted` isn't available on this riverpod version — track
    // disposal manually via `onDispose` so the debounce wait below can
    // abandon a superseded (older-keystroke) family entry without calling
    // the service.
    var disposed = false;
    ref.onDispose(() => disposed = true);

    final debounce = ref.watch(textSearchDebounceDurationProvider);
    if (debounce > Duration.zero) {
      await Future<void>.delayed(debounce);
    }
    // A newer keystroke's family entry superseded this one while we were
    // waiting out the debounce — abandon silently, never call the service.
    if (disposed) return const [];

    final position = await ref.watch(gymSearchLocationBiasProvider.future);
    final cacheKey = _textSearchCacheKey(trimmed, position);

    final cache = ref.watch(textSearchCacheProvider);
    final cached = cache.get(cacheKey, now: DateTime.now());
    if (cached != null) return cached;

    final service = ref.watch(placesTextSearchServiceProvider);
    final results = await service.search(
      textQuery: trimmed,
      biasLatitude: position?.latitude,
      biasLongitude: position?.longitude,
    );

    cache.put(cacheKey, results);
    return results;
  },
);
