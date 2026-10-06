import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/coach/domain/trainer_location.dart';
import 'package:treino/features/gyms/domain/gym.dart';
import 'package:treino/features/gyms/domain/gym_source.dart';

Gym _gym({
  required GymSource source,
  DateTime? coordsFetchedAt,
}) =>
    Gym(
      id: 'ChIJabc',
      name: 'Gym X',
      lat: -34.6,
      lng: -58.4,
      geohash: '69y7p',
      source: source,
      createdAt: DateTime.utc(2026, 1, 1),
      coordsFetchedAt: coordsFetchedAt,
    );

void main() {
  group('trainerLocationFromGym (#1338)', () {
    test(
        'gym de Google: copia placeId y coordsFetchedAt para que el job lo refresque',
        () {
      final fetched = DateTime.utc(2026, 9, 20);
      final l = trainerLocationFromGym(
        _gym(source: GymSource.googlePlaces, coordsFetchedAt: fetched),
      );

      expect(l.type, TrainerLocationType.gym);
      expect(l.id, 'gym-ChIJabc');
      expect(l.gymId, 'ChIJabc');
      expect(l.lat, -34.6);
      expect(l.geohash, '69y7p');
      expect(l.placeId, 'ChIJabc');
      expect(l.coordsFetchedAt, fetched);
    });

    test(
        'gym de Google sin coordsFetchedAt: lo deja null (lo cubre la migración)',
        () {
      final l = trainerLocationFromGym(_gym(source: GymSource.googlePlaces));
      expect(l.placeId, 'ChIJabc');
      expect(l.coordsFetchedAt, isNull);
    });

    test('gym seed / self-service: sin placeId ni coordsFetchedAt', () {
      for (final s in [GymSource.seed, GymSource.selfService]) {
        final l = trainerLocationFromGym(
          _gym(source: s, coordsFetchedAt: DateTime.utc(2026, 9, 20)),
        );
        expect(l.placeId, isNull, reason: '$s');
        expect(l.coordsFetchedAt, isNull, reason: '$s');
      }
    });
  });
}
