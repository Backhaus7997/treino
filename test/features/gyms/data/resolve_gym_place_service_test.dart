// Plan B REWORK — gym-google-places.
//
// resolveGymPlace CANNOT be deployed as a Cloud Function: GCP project
// treino-dev sits under org code-assurance.com whose Domain-Restricted-
// Sharing policy blocks public (allUsers) invoker on Cloud Functions. This
// pivots Place Details resolution to CLIENT-SIDE:
//   1. Read-through cache via GymRepository.getById(placeId).
//   2. On miss: GET Place Details (New) with PLACES_CLIENT_KEY, map to Gym,
//      upsert gyms/{placeId} via GymRepository.upsert.
//   3. Errors never crash — surfaced as ResolveGymPlaceFailure.
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:treino/features/gyms/data/gym_repository.dart';
import 'package:treino/features/gyms/data/resolve_gym_place_service.dart';
import 'package:treino/features/gyms/domain/gym_source.dart';

class MockHttpClient extends Mock implements http.Client {}

void main() {
  setUpAll(() {
    registerFallbackValue(Uri.parse('https://example.com'));
  });

  late FakeFirebaseFirestore firestore;
  late GymRepository gymRepository;
  late MockHttpClient mockClient;
  late ResolveGymPlaceService sut;

  http.Response okResponse(Map<String, dynamic> body) =>
      http.Response(jsonEncode(body), 200);

  setUp(() {
    firestore = FakeFirebaseFirestore();
    gymRepository = GymRepository(firestore: firestore);
    mockClient = MockHttpClient();
    sut = ResolveGymPlaceService(
      gymRepository: gymRepository,
      httpClient: mockClient,
      clientApiKey: 'test-client-key',
    );
  });

  group('ResolveGymPlaceService.call — read-through cache', () {
    test('cache hit: returns the existing gym without calling http', () async {
      await firestore.collection('gyms').doc('ChIJ_place_1').set({
        'name': 'SportClub Belgrano',
        'address': 'Cabildo 1789, CABA',
        'lat': -34.5598,
        'lng': -58.4615,
        'geohash': '6d6m7',
        'source': 'google-places',
        'createdAt': Timestamp.fromDate(DateTime.utc(2026, 1, 1)),
      });

      final result = await sut.call(placeId: 'ChIJ_place_1');

      expect(result.gymId, 'ChIJ_place_1');
      expect(result.name, 'SportClub Belgrano');
      verifyNever(() => mockClient.get(any(), headers: any(named: 'headers')));
    });
  });

  group('ResolveGymPlaceService.call — cache miss', () {
    test('GETs Place Details (New) with the field mask and client key',
        () async {
      when(() => mockClient.get(any(), headers: any(named: 'headers')))
          .thenAnswer((_) async => okResponse({
                'id': 'ChIJ_place_2',
                'displayName': {'text': 'Megatlon Recoleta'},
                'formattedAddress': 'Av. Callao 1234, CABA',
                'location': {'latitude': -34.59, 'longitude': -58.39},
                'types': ['gym', 'health'],
              }));

      await sut.call(placeId: 'ChIJ_place_2');

      final captured = verify(() => mockClient.get(
            captureAny(),
            headers: captureAny(named: 'headers'),
          )).captured;

      final uri = captured[0] as Uri;
      final headers = captured[1] as Map<String, String>;

      expect(
        uri.toString(),
        'https://places.googleapis.com/v1/places/ChIJ_place_2',
      );
      expect(headers['X-Goog-Api-Key'], 'test-client-key');
      expect(
        headers['X-Goog-FieldMask'],
        'id,displayName,formattedAddress,location,types',
      );
    });

    test('appends sessionToken as a query param when provided', () async {
      when(() => mockClient.get(any(), headers: any(named: 'headers')))
          .thenAnswer((_) async => okResponse({
                'id': 'ChIJ_place_2',
                'displayName': {'text': 'Megatlon Recoleta'},
                'formattedAddress': 'Av. Callao 1234, CABA',
                'location': {'latitude': -34.59, 'longitude': -58.39},
                'types': ['gym'],
              }));

      await sut.call(placeId: 'ChIJ_place_2', sessionToken: 'tok-1');

      final captured = verify(() =>
              mockClient.get(captureAny(), headers: any(named: 'headers')))
          .captured;
      final uri = captured.single as Uri;
      expect(uri.queryParameters['sessionToken'], 'tok-1');
    });

    test('maps the Place Details response onto a Gym and upserts it', () async {
      when(() => mockClient.get(any(), headers: any(named: 'headers')))
          .thenAnswer((_) async => okResponse({
                'id': 'ChIJ_place_3',
                'displayName': {'text': 'SmartFit Caballito'},
                'formattedAddress': 'Rivadavia 5000, CABA',
                'location': {'latitude': -34.61, 'longitude': -58.44},
                'types': ['gym'],
              }));

      final result = await sut.call(placeId: 'ChIJ_place_3');

      expect(result.gymId, 'ChIJ_place_3');
      expect(result.name, 'SmartFit Caballito');
      expect(result.address, 'Rivadavia 5000, CABA');
      expect(result.source, 'google-places');

      final stored = await gymRepository.getById('ChIJ_place_3');
      expect(stored, isNotNull);
      expect(stored!.name, 'SmartFit Caballito');
      expect(stored.lat, -34.61);
      expect(stored.lng, -58.44);
      expect(stored.source, GymSource.googlePlaces);
      expect(stored.brandId, isNull);
      expect(stored.branchName, isNull);
    });

    test('second call for the same placeId hits the cache, not http', () async {
      when(() => mockClient.get(any(), headers: any(named: 'headers')))
          .thenAnswer((_) async => okResponse({
                'id': 'ChIJ_place_4',
                'displayName': {'text': 'Cacheado Gym'},
                'formattedAddress': null,
                'location': {'latitude': 0.0, 'longitude': 0.0},
                'types': ['gym'],
              }));

      await sut.call(placeId: 'ChIJ_place_4');
      await sut.call(placeId: 'ChIJ_place_4');

      verify(() => mockClient.get(any(), headers: any(named: 'headers')))
          .called(1);
    });
  });

  group('ResolveGymPlaceService.call — errors', () {
    test('empty client key surfaces a clear error, never calls http', () async {
      final noKeySut = ResolveGymPlaceService(
        gymRepository: gymRepository,
        httpClient: mockClient,
        clientApiKey: '',
      );

      await expectLater(
        () => noKeySut.call(placeId: 'ChIJ_place_5'),
        throwsA(isA<ResolveGymPlaceFailure>()),
      );
      verifyNever(() => mockClient.get(any(), headers: any(named: 'headers')));
    });

    test('non-200 response throws ResolveGymPlaceFailure, never leaks key',
        () async {
      when(() => mockClient.get(any(), headers: any(named: 'headers')))
          .thenAnswer((_) async => http.Response('server error', 500));

      await expectLater(
        () => sut.call(placeId: 'ChIJ_place_6'),
        throwsA(
          predicate<ResolveGymPlaceFailure>(
            (e) => !e.toString().contains('test-client-key'),
          ),
        ),
      );
    });

    test('network exception propagates as ResolveGymPlaceFailure', () async {
      when(() => mockClient.get(any(), headers: any(named: 'headers')))
          .thenThrow(Exception('socket closed'));

      await expectLater(
        () => sut.call(placeId: 'ChIJ_place_7'),
        throwsA(isA<ResolveGymPlaceFailure>()),
      );
    });

    test('incomplete Places response (missing location) throws', () async {
      when(() => mockClient.get(any(), headers: any(named: 'headers')))
          .thenAnswer((_) async => okResponse({
                'id': 'ChIJ_place_8',
                'displayName': {'text': 'Incompleto'},
              }));

      await expectLater(
        () => sut.call(placeId: 'ChIJ_place_8'),
        throwsA(isA<ResolveGymPlaceFailure>()),
      );
    });

    test('empty placeId throws without calling http', () async {
      await expectLater(
        () => sut.call(placeId: ''),
        throwsA(isA<ResolveGymPlaceFailure>()),
      );
      verifyNever(() => mockClient.get(any(), headers: any(named: 'headers')));
    });
  });
}
