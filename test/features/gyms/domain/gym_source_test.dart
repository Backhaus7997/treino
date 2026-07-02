import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/gyms/domain/gym_source.dart';

// T2.2 RED / T2.3 GREEN — gym-google-places Phase 2.
void main() {
  group('GymSource.googlePlaces', () {
    test('toWire() maps googlePlaces to "google-places"', () {
      expect(GymSource.googlePlaces.toWire(), 'google-places');
    });

    test('gymSourceFromString() round-trips "google-places"', () {
      expect(gymSourceFromString('google-places'), GymSource.googlePlaces);
    });

    test('gymSourceFromString() is case/whitespace tolerant', () {
      expect(gymSourceFromString('  Google-Places  '), GymSource.googlePlaces);
    });

    test('existing sources still round-trip (no regression)', () {
      expect(gymSourceFromString('seed'), GymSource.seed);
      expect(gymSourceFromString('self-service'), GymSource.selfService);
      expect(GymSource.seed.toWire(), 'seed');
      expect(GymSource.selfService.toWire(), 'self-service');
    });

    test('unknown wire value returns null', () {
      expect(gymSourceFromString('unknown-source'), isNull);
    });
  });
}
