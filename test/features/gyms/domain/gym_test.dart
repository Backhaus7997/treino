import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/gyms/domain/gym.dart';

// ignore_for_file: avoid_dynamic_calls

Map<String, Object?> _baseDoc({
  String name = 'SportClub - Belgrano',
  String? address = 'Cabildo 1789 - Belgrano',
  double lat = -34.5598,
  double lng = -58.4615,
  String geohash = '6ezhg',
  String source = 'seed',
  String? createdBy,
}) =>
    {
      'name': name,
      'address': address,
      'lat': lat,
      'lng': lng,
      'geohash': geohash,
      'source': source,
      'createdBy': createdBy,
      'createdAt': Timestamp.fromDate(DateTime.utc(2026, 1, 1)),
    };

void main() {
  group('Gym.fromJson — brand fields (new docs)', () {
    test('decodes doc WITH brandId/brandName/branchName', () {
      final json = {
        ..._baseDoc(),
        'id': 'sportclub-belgrano',
        'brandId': 'sportclub',
        'brandName': 'SportClub',
        'branchName': 'Belgrano',
      };

      final gym = Gym.fromJson(json);

      expect(gym.id, 'sportclub-belgrano');
      expect(gym.brandId, 'sportclub');
      expect(gym.brandName, 'SportClub');
      expect(gym.branchName, 'Belgrano');
    });

    test('decodes independent gym with brandId mapping to itself', () {
      final json = {
        ..._baseDoc(name: 'Sieger Gym'),
        'id': 'sieger-gym-cba',
        'brandId': 'sieger-gym-cba',
        'brandName': 'Sieger Gym',
        'branchName': null,
      };

      final gym = Gym.fromJson(json);

      expect(gym.brandId, gym.id);
      expect(gym.branchName, isNull);
    });
  });

  group('Gym.fromJson — backward compat (old docs without brand fields)', () {
    test('decodes OLD doc WITHOUT brand fields — brand fields are null', () {
      final json = {
        ..._baseDoc(name: 'Megatlon Belgrano'),
        'id': 'megatlon-belgrano',
      };

      final gym = Gym.fromJson(json);

      expect(gym.id, 'megatlon-belgrano');
      expect(gym.name, 'Megatlon Belgrano');
      expect(gym.brandId, isNull);
      expect(gym.brandName, isNull);
      expect(gym.branchName, isNull);
    });

    test('decodes OLD doc WITHOUT city/province — both are null', () {
      final json = {
        ..._baseDoc(name: 'Megatlon Belgrano'),
        'id': 'megatlon-belgrano',
      };

      final gym = Gym.fromJson(json);

      expect(gym.city, isNull);
      expect(gym.province, isNull);
    });
  });

  group('Gym.fromJson — optional city/province (new docs)', () {
    test('decodes doc WITH city/province', () {
      final json = {
        ..._baseDoc(),
        'id': 'sportclub-belgrano',
        'city': 'CABA',
        'province': 'Buenos Aires',
      };

      final gym = Gym.fromJson(json);

      expect(gym.city, 'CABA');
      expect(gym.province, 'Buenos Aires');
    });
  });

  group('Gym.fromJson — required geo fields (unchanged)', () {
    test('still requires lat/lng/geohash — throws when missing', () {
      final json = {
        'id': 'broken-gym',
        'name': 'Broken Gym',
        'source': 'seed',
        'createdAt': Timestamp.fromDate(DateTime.utc(2026, 1, 1)),
      };

      expect(() => Gym.fromJson(json), throwsA(anything));
    });

    test('parses valid lat/lng/geohash into the right types', () {
      final json = {
        ..._baseDoc(),
        'id': 'sportclub-belgrano',
      };

      final gym = Gym.fromJson(json);

      expect(gym.lat, isA<double>());
      expect(gym.lng, isA<double>());
      expect(gym.geohash, isA<String>());
    });
  });
}
