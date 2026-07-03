import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/gyms/domain/nearby_gym.dart';

// Task 1.1 RED / 1.2 GREEN — gym-selection-v2 Phase 1.
//
// Plain DTO (mirrors GymSuggestion's non-freezed style) mapped from a
// `places:searchNearby` (New) response. Carries lat/lng — unlike
// GymSuggestion — because nearby rows need client-side haversine distance
// labels (design AD-6/AD-8).
void main() {
  group('NearbyGym', () {
    test('constructs with placeId/name/address/lat/lng', () {
      const gym = NearbyGym(
        placeId: 'ChIJ_place_1',
        name: 'SportClub Belgrano',
        address: 'Cabildo 1789, CABA',
        lat: -34.5598,
        lng: -58.4615,
      );

      expect(gym.placeId, 'ChIJ_place_1');
      expect(gym.name, 'SportClub Belgrano');
      expect(gym.address, 'Cabildo 1789, CABA');
      expect(gym.lat, -34.5598);
      expect(gym.lng, -58.4615);
    });

    test('address is nullable (some results omit formattedAddress)', () {
      const gym = NearbyGym(
        placeId: 'ChIJ_place_2',
        name: 'Gimnasio Local',
        address: null,
        lat: -34.5,
        lng: -58.4,
      );

      expect(gym.address, isNull);
    });

    test('equality is value-based', () {
      const a = NearbyGym(
        placeId: 'ChIJ_place_1',
        name: 'SportClub Belgrano',
        address: 'Cabildo 1789, CABA',
        lat: -34.5598,
        lng: -58.4615,
      );
      const b = NearbyGym(
        placeId: 'ChIJ_place_1',
        name: 'SportClub Belgrano',
        address: 'Cabildo 1789, CABA',
        lat: -34.5598,
        lng: -58.4615,
      );
      const c = NearbyGym(
        placeId: 'ChIJ_place_other',
        name: 'SportClub Belgrano',
        address: 'Cabildo 1789, CABA',
        lat: -34.5598,
        lng: -58.4615,
      );

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a == c, isFalse);
    });
  });
}
