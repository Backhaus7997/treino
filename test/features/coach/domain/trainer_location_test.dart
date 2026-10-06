import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/coach/domain/trainer_location.dart';

void main() {
  group('TrainerLocation (políticas de Places)', () {
    test('un doc legacy sin placeId/coordsFetchedAt/stale sigue parseando', () {
      final l = TrainerLocation.fromJson({
        'id': 'custom-1',
        'type': 'custom',
        'customLabel': 'Mi estudio',
        'lat': -34.6,
        'lng': -58.4,
        'geohash': '69y7p',
      });

      expect(l.placeId, isNull);
      expect(l.coordsFetchedAt, isNull);
      expect(l.stale, isNull);
      expect(l.customLabel, 'Mi estudio');
    });

    test('round-trip: placeId y coordsFetchedAt viajan como Timestamp', () {
      final cuando = DateTime.utc(2026, 10, 6, 12);
      final l = TrainerLocation(
        id: 'custom-1',
        type: TrainerLocationType.custom,
        customLabel: 'Mi estudio',
        lat: -34.6,
        lng: -58.4,
        geohash: '69y7p',
        placeId: 'ChIJabc',
        coordsFetchedAt: cuando,
      );

      final json = l.toJson();
      expect(json['placeId'], 'ChIJabc');
      expect(json['coordsFetchedAt'], isA<Timestamp>());

      final vuelta = TrainerLocation.fromJson(json);
      expect(vuelta.placeId, 'ChIJabc');
      expect(vuelta.coordsFetchedAt, cuando);
    });

    test('stale se lee cuando el servidor lo marca', () {
      final l = TrainerLocation.fromJson({
        'id': 'custom-1',
        'type': 'custom',
        'lat': 1.0,
        'lng': 2.0,
        'geohash': 'abcde',
        'placeId': 'ChIJabc',
        'stale': true,
      });
      expect(l.stale, isTrue);
    });

    test('un lugar stale sin coordenadas (purga de 30 días) parsea sin romper',
        () {
      final l = TrainerLocation.fromJson({
        'id': 'custom-1',
        'type': 'custom',
        'customLabel': 'Mi estudio',
        'lat': null,
        'lng': null,
        'geohash': null,
        'placeId': 'ChIJabc',
        'stale': true,
      });

      expect(l.lat, isNull);
      expect(l.lng, isNull);
      expect(l.geohash, isNull);
      expect(l.stale, isTrue);
      expect(l.placeId, 'ChIJabc');
      expect(l.isPublishable, isFalse);
    });

    test('también parsea si los campos de coordenadas faltan del doc', () {
      final l = TrainerLocation.fromJson({
        'id': 'custom-1',
        'type': 'custom',
        'placeId': 'ChIJabc',
        'stale': true,
      });
      expect(l.lat, isNull);
      expect(l.isPublishable, isFalse);
    });

    test('isPublishable: solo con coordenadas y sin stale', () {
      TrainerLocation de({double? lat, double? lng, bool? stale}) =>
          TrainerLocation(
            id: 'x',
            type: TrainerLocationType.custom,
            lat: lat,
            lng: lng,
            geohash: lat == null ? null : 'abcde',
            stale: stale,
          );

      expect(de(lat: 1, lng: 2).isPublishable, isTrue);
      expect(de(lat: 1, lng: 2, stale: false).isPublishable, isTrue);
      expect(de(lat: 1, lng: 2, stale: true).isPublishable, isFalse);
      expect(de(lat: 1).isPublishable, isFalse);
      expect(de(lng: 2).isPublishable, isFalse);
      expect(de().isPublishable, isFalse);
    });
  });
}
