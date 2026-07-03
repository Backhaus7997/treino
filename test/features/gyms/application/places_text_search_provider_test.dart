// Task 3.4 RED / 3.5 GREEN — gym-selection-v2 Phase 3 (addendum, AD-12).
//
// placesTextSearchProvider is the highest-risk piece of this addendum: Text
// Search bills as Text Search Pro (~$32/1000, no free session), same tier as
// searchNearby. Cost gating is STRUCTURAL and provider-owned, verified here
// with a call-counting fake PlacesTextSearchService:
//   (a) rapid-fire query changes within the debounce window collapse to a
//       SINGLE call for the final settled query.
//   (b) queries under 3 characters never call the service.
//   (c) a repeat of the same settled query (+ same bias bucket, or
//       query-only when no location) within the cache TTL is a cache hit —
//       zero additional calls.
//   (d) a different query, different bias bucket, or expired TTL triggers a
//       new call.
//
// Debounce is provider-owned and test-controllable via
// `textSearchDebounceDurationProvider` (overridden to a near-zero duration
// here) — mirrors the design's "inject the debounce duration... so tests
// don't sleep" instruction without a real 600ms wall-clock wait.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:treino/features/gyms/application/places_providers.dart';
import 'package:treino/features/gyms/data/places_text_search_service.dart';
import 'package:treino/features/gyms/domain/gym_suggestion.dart';

/// Call-counting fake — NOT a mocktail mock, matching
/// `nearby_gyms_provider_test.dart`'s convention.
class _CountingTextSearchService implements PlacesTextSearchService {
  int callCount = 0;
  List<String> queriesReceived = [];
  List<GymSuggestion> results = const [
    GymSuggestion(
      placeId: 'ChIJ_1',
      primaryText: 'QIVOX Villa Warcalde',
      secondaryText: 'Some street 123',
    ),
  ];

  @override
  Future<List<GymSuggestion>> search({
    required String textQuery,
    double? biasLatitude,
    double? biasLongitude,
    int biasRadiusMeters = PlacesTextSearchService.defaultBiasRadiusMeters,
    int pageSize = PlacesTextSearchService.defaultPageSize,
  }) async {
    callCount++;
    queriesReceived.add(textQuery);
    return results;
  }
}

void main() {
  // Near-zero so tests don't sleep for the real 600ms debounce window, but
  // still exercises real Future-based scheduling (not a synchronous no-op).
  const testDebounce = Duration(milliseconds: 1);

  ProviderContainer buildContainer(_CountingTextSearchService fake) =>
      ProviderContainer(
        overrides: [
          placesTextSearchServiceProvider.overrideWithValue(fake),
          textSearchDebounceDurationProvider.overrideWithValue(testDebounce),
          gymSearchLocationBiasProvider.overrideWith((ref) async => null),
        ],
      );

  group('placesTextSearchProvider — debounce collapses rapid changes', () {
    test(
        'switching the watched query mid-debounce abandons the superseded '
        'entry — only the final settled query calls the service', () async {
      final fake = _CountingTextSearchService();
      final container = buildContainer(fake);
      addTearDown(container.dispose);

      // Simulate rapid keystrokes: the WIDGET watches a new family entry
      // (query string) on every keystroke — `_SuggestionsList` only ever
      // has ONE active listener, on the LATEST query. Switching the
      // listened-to entry before the debounce elapses is what makes the
      // superseded entries' `onDispose` fire (autoDispose has no more
      // listeners) — this IS the debounce-cancellation mechanism.
      ProviderSubscription<AsyncValue<List<GymSuggestion>>>? sub;
      for (final partial in ['q', 'qi', 'qiv', 'qivo', 'qivox']) {
        sub?.close();
        sub = container.listen(placesTextSearchProvider(partial), (_, __) {});
      }

      final result =
          await container.read(placesTextSearchProvider('qivox').future);
      sub?.close();

      expect(result, hasLength(1));
      expect(fake.callCount, 1);
      expect(fake.queriesReceived, ['qivox']);
    });
  });

  /// Reads [provider] the way a mounted widget would (`ref.watch` inside a
  /// build method keeps a live listener) — a bare `container.read(.future)`
  /// with NO listener lets `autoDispose` tear the entry down mid-debounce
  /// (confirmed: `ref.onDispose` fires during the `Future.delayed` gap),
  /// which is exactly the cancellation signal 3.5's debounce relies on for
  /// SUPERSEDED entries. For a settled, still-watched query this would be a
  /// false cancellation — so every "this query should actually resolve"
  /// assertion below holds a subscription open across the read, mirroring
  /// production's `ref.watch(placesTextSearchProvider(activeQuery))`.
  Future<List<GymSuggestion>> settle(
    ProviderContainer container,
    String query,
  ) async {
    final sub = container.listen(placesTextSearchProvider(query), (_, __) {});
    final result = await container.read(placesTextSearchProvider(query).future);
    sub.close();
    return result;
  }

  group('placesTextSearchProvider — minimum 3 characters', () {
    test('queries under 3 characters never call the service', () async {
      final fake = _CountingTextSearchService();
      final container = buildContainer(fake);
      addTearDown(container.dispose);

      final oneChar = await settle(container, 'q');
      final twoChar = await settle(container, 'qi');

      expect(oneChar, isEmpty);
      expect(twoChar, isEmpty);
      expect(fake.callCount, 0);
    });

    test('a 3-character query does call the service', () async {
      final fake = _CountingTextSearchService();
      final container = buildContainer(fake);
      addTearDown(container.dispose);

      final result = await settle(container, 'qiv');

      expect(result, hasLength(1));
      expect(fake.callCount, 1);
    });
  });

  group('placesTextSearchProvider — cache (query + bias bucket, TTL)', () {
    test(
        'repeating the same settled query within TTL is a cache hit — zero '
        'additional calls', () async {
      final fake = _CountingTextSearchService();
      final container = buildContainer(fake);
      addTearDown(container.dispose);

      await settle(container, 'qivox');
      expect(fake.callCount, 1);

      // Simulate the family entry being disposed/re-read (e.g. widget
      // rebuild cycles) for the SAME query — must be a cache hit.
      container.invalidate(placesTextSearchProvider('qivox'));
      final second = await settle(container, 'qivox');

      expect(second, hasLength(1));
      expect(fake.callCount, 1,
          reason: 'same settled query within TTL must be a cache hit');
    });

    test('a different query triggers a distinct (second) call', () async {
      final fake = _CountingTextSearchService();
      final container = buildContainer(fake);
      addTearDown(container.dispose);

      await settle(container, 'qivox');
      expect(fake.callCount, 1);

      await settle(container, 'megatlon');

      expect(fake.callCount, 2,
          reason: 'a different query text is a cache miss — must fetch');
    });

    test(
        'the same query text with a DIFFERENT bias bucket triggers a '
        'distinct (second) call', () async {
      final fake = _CountingTextSearchService();

      // No-location container (bucket is the empty/no-location key).
      final noLocationContainer = ProviderContainer(
        overrides: [
          placesTextSearchServiceProvider.overrideWithValue(fake),
          textSearchDebounceDurationProvider.overrideWithValue(testDebounce),
          gymSearchLocationBiasProvider.overrideWith((ref) async => null),
        ],
      );
      addTearDown(noLocationContainer.dispose);
      await settle(noLocationContainer, 'qivox');
      expect(fake.callCount, 1);

      // A biased container sharing the SAME cache instance — a DIFFERENT
      // cache key (query + real geohash bucket vs query-only) must be a
      // cache miss even though the query text is identical.
      final sharedCache = noLocationContainer.read(textSearchCacheProvider);
      final biasedContainer = ProviderContainer(
        overrides: [
          placesTextSearchServiceProvider.overrideWithValue(fake),
          textSearchDebounceDurationProvider.overrideWithValue(testDebounce),
          textSearchCacheProvider.overrideWithValue(sharedCache),
          gymSearchLocationBiasProvider.overrideWith(
            (ref) async => Position(
              latitude: -34.5598,
              longitude: -58.4615,
              timestamp: DateTime(2025),
              accuracy: 5,
              altitude: 0,
              altitudeAccuracy: 0,
              heading: 0,
              headingAccuracy: 0,
              speed: 0,
              speedAccuracy: 0,
            ),
          ),
        ],
      );
      addTearDown(biasedContainer.dispose);
      await settle(biasedContainer, 'qivox');

      expect(fake.callCount, 2,
          reason: 'switching from no-location to a real bias bucket is a cache '
              'miss for the same query text');
    });

    test('an expired TTL entry triggers a distinct (second) call', () async {
      final fake = _CountingTextSearchService();
      final container = ProviderContainer(
        overrides: [
          placesTextSearchServiceProvider.overrideWithValue(fake),
          textSearchDebounceDurationProvider.overrideWithValue(testDebounce),
          gymSearchLocationBiasProvider.overrideWith((ref) async => null),
          // Inject an already-expired cache holder so the TTL-expiry branch
          // is exercised deterministically, without a real 10-minute wait.
          textSearchCacheProvider.overrideWithValue(
            TextSearchCache()
              ..put(
                'qivox|',
                const [],
                fetchedAt: DateTime.now().subtract(
                  textSearchCacheTtl + const Duration(seconds: 1),
                ),
              ),
          ),
        ],
      );
      addTearDown(container.dispose);

      final result = await settle(container, 'qivox');

      expect(result, hasLength(1));
      expect(fake.callCount, 1,
          reason: 'an expired TTL entry must be treated as a cache miss');
    });
  });
}
