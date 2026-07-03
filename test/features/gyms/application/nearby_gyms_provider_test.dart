// Task 1.6/1.7 RED / 1.8/1.9 GREEN — gym-selection-v2 Phase 1.
//
// nearbyGymsProvider is the highest-risk piece of this slice: searchNearby
// bills as Nearby Search Pro (~$32/1000, no free session). Cost gating is
// STRUCTURAL and provider-owned (design AD-2/AD-9), verified here with a
// call-counting fake PlacesNearbySearchService:
//   1. Fire-once-per-open floor: N rebuilds of the same bucket → 1 call.
//   2. Cross-open TTL cache: the FAMILY entry is `autoDispose` — closing the
//      screen disposes it (simulated here via `container.invalidate` +
//      letting the autoDispose timer/`read` re-create the entry, exactly
//      what happens on real screen re-open within one app session/
//      ProviderContainer). Re-reading the SAME bucket within TTL must be a
//      cache hit (0 extra calls) because `nearbyGymsCacheProvider` is
//      `keepAlive` and survives the family entry's disposal. A DIFFERENT
//      bucket, or an expired TTL, must trigger a distinct (new) call.
//
// NOTE: `nearbyGymsCacheProvider`'s Map lives inside ONE ProviderContainer —
// exactly like the real app (a single root ProviderScope for the whole
// session). Simulating "screen re-open" with a second, separate
// ProviderContainer would NOT exercise the cache (a fresh container has a
// fresh, empty cache Map) — it would only prove the fire-once floor twice
// over. The real "re-open" signal is the autoDispose family entry going
// away and coming back, which is what these tests do.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/gyms/application/places_providers.dart';
import 'package:treino/features/gyms/data/places_nearby_search_service.dart';
import 'package:treino/features/gyms/domain/nearby_gym.dart';

/// Call-counting fake — NOT a mocktail mock, so the call count is a plain,
/// unambiguous `int` assertion (design's "call-counting fake service"
/// wording, distinct from `verify(...).called(1)` on a Mock).
class _CountingNearbySearchService implements PlacesNearbySearchService {
  int callCount = 0;
  List<NearbyGym> results = const [
    NearbyGym(
      placeId: 'ChIJ_1',
      name: 'SportClub Belgrano',
      address: 'Cabildo 1789',
      lat: -34.5598,
      lng: -58.4615,
    ),
  ];

  @override
  Future<List<NearbyGym>> search({
    required double latitude,
    required double longitude,
    int radiusMeters = PlacesNearbySearchService.defaultRadiusMeters,
    int maxResultCount = PlacesNearbySearchService.defaultMaxResultCount,
  }) async {
    callCount++;
    return results;
  }
}

void main() {
  const bucketA = 'x1y2z';
  const bucketB = 'a9b8c';

  group('nearbyGymsProvider — fire-once-per-open floor (1.6)', () {
    test(
        'fires the fake exactly once across N forced rebuilds of the same '
        'bucket', () async {
      final fake = _CountingNearbySearchService();
      final container = ProviderContainer(
        overrides: [
          placesNearbySearchServiceProvider.overrideWithValue(fake),
        ],
      );
      addTearDown(container.dispose);

      // First read triggers the fetch.
      final first = await container.read(nearbyGymsProvider(bucketA).future);
      expect(first, hasLength(1));
      expect(fake.callCount, 1);

      // Force N rebuilds by re-reading the SAME family entry repeatedly (and
      // keeping a listener alive in between, like a widget subscription
      // would) — Riverpod memoizes it; none of these should re-invoke the
      // service.
      final sub = container.listen(nearbyGymsProvider(bucketA), (_, __) {});
      addTearDown(sub.close);
      for (var i = 0; i < 5; i++) {
        final again = await container.read(nearbyGymsProvider(bucketA).future);
        expect(again, hasLength(1));
      }

      expect(fake.callCount, 1);
    });
  });

  group('nearbyGymsProvider — cross-open TTL cache (1.7)', () {
    test(
        'invalidating the family entry (simulated re-open) for the SAME '
        'bucket within TTL makes zero additional calls (cache hit)', () async {
      final fake = _CountingNearbySearchService();
      final container = ProviderContainer(
        overrides: [
          placesNearbySearchServiceProvider.overrideWithValue(fake),
        ],
      );
      addTearDown(container.dispose);

      // "First screen open."
      await container.read(nearbyGymsProvider(bucketA).future);
      expect(fake.callCount, 1);

      // Simulate the screen closing (autoDispose family entry torn down)
      // and reopening: invalidate the family entry, then read it again.
      container.invalidate(nearbyGymsProvider(bucketA));
      final second = await container.read(nearbyGymsProvider(bucketA).future);

      expect(second, hasLength(1));
      expect(
        fake.callCount,
        1,
        reason: 'same-bucket re-open within TTL must be a cache hit — zero '
            'additional network calls',
      );
    });

    test('a DIFFERENT bucket triggers a distinct (second) call', () async {
      final fake = _CountingNearbySearchService();
      final container = ProviderContainer(
        overrides: [
          placesNearbySearchServiceProvider.overrideWithValue(fake),
        ],
      );
      addTearDown(container.dispose);

      await container.read(nearbyGymsProvider(bucketA).future);
      expect(fake.callCount, 1);

      container.invalidate(nearbyGymsProvider(bucketA));
      await container.read(nearbyGymsProvider(bucketB).future);

      expect(fake.callCount, 2,
          reason: 'a different geohash bucket is a cache miss — must fetch');
    });

    test(
        'an expired TTL entry triggers a distinct (second) call for the '
        'SAME bucket', () async {
      final fake = _CountingNearbySearchService();
      final container = ProviderContainer(
        overrides: [
          placesNearbySearchServiceProvider.overrideWithValue(fake),
          // Inject an already-expired cache holder so the TTL-expiry branch
          // is exercised deterministically, without a real 10-minute wait.
          nearbyGymsCacheProvider.overrideWithValue(
            NearbyGymsCache()
              ..put(
                bucketA,
                const [],
                fetchedAt: DateTime.now().subtract(
                  nearbyGymsCacheTtl + const Duration(seconds: 1),
                ),
              ),
          ),
        ],
      );
      addTearDown(container.dispose);

      final result = await container.read(nearbyGymsProvider(bucketA).future);

      expect(result, hasLength(1));
      expect(fake.callCount, 1,
          reason: 'an expired TTL entry must be treated as a cache miss');
    });
  });
}
