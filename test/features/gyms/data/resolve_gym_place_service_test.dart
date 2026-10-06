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
import 'package:treino/core/moderation/moderation_guard.dart';
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

  Map<String, Object?> detailsBody() => {
        'id': 'ChIJ_place_2',
        'displayName': {'text': 'Texto de Google que NO se guarda'},
        'formattedAddress': 'Dirección de Google que NO se guarda',
        'location': {'latitude': -34.61, 'longitude': -58.44},
      };

  group('ResolveGymPlaceService.call — read-through cache', () {
    test('cache hit: returns the existing gym without calling http', () async {
      await firestore.collection('gyms').doc('ChIJ_place_1').set({
        'name': 'SportClub Belgrano',
        'lat': -34.5598,
        'lng': -58.4615,
        'geohash': '6d6m7',
        'source': 'google-places',
        'createdAt': Timestamp.fromDate(DateTime.utc(2026, 1, 1)),
      });

      final result = await sut.call(placeId: 'ChIJ_place_1');

      expect(result.gymId, 'ChIJ_place_1');
      expect(result.name, 'SportClub Belgrano');
      expect(result.needsName, isFalse);
      verifyNever(() => mockClient.get(any(), headers: any(named: 'headers')));
    });

    test('cache hit ignores a typed name: the first user\'s name wins',
        () async {
      await firestore.collection('gyms').doc('ChIJ_place_1').set({
        'name': 'SportClub Belgrano',
        'lat': -34.5598,
        'lng': -58.4615,
        'geohash': '6d6m7',
        'source': 'google-places',
        'createdAt': Timestamp.fromDate(DateTime.utc(2026, 1, 1)),
      });

      final result =
          await sut.call(placeId: 'ChIJ_place_1', name: 'Otro nombre');

      expect(result.name, 'SportClub Belgrano');
      final doc = await firestore.collection('gyms').doc('ChIJ_place_1').get();
      expect(doc.data()!['name'], 'SportClub Belgrano');
    });

    test('gym flagged nameNeeded and no name typed: asks for it, no write',
        () async {
      await firestore.collection('gyms').doc('ChIJ_place_9').set({
        'name': 'Marcador',
        'nameNeeded': true,
        'lat': -34.5,
        'lng': -58.4,
        'geohash': '6d6m7',
        'source': 'google-places',
        'createdAt': Timestamp.fromDate(DateTime.utc(2026, 1, 1)),
      });

      final result = await sut.call(placeId: 'ChIJ_place_9');

      expect(result.needsName, isTrue);
      expect(result.gymId, 'ChIJ_place_9');
      verifyNever(() => mockClient.get(any(), headers: any(named: 'headers')));
    });

    test('gym flagged nameNeeded and a name typed: stores it, clears the flag',
        () async {
      await firestore.collection('gyms').doc('ChIJ_place_9').set({
        'name': 'Marcador',
        'nameNeeded': true,
        'lat': -34.5,
        'lng': -58.4,
        'geohash': '6d6m7',
        'source': 'google-places',
        'createdAt': Timestamp.fromDate(DateTime.utc(2026, 1, 1)),
      });

      final result =
          await sut.call(placeId: 'ChIJ_place_9', name: '  Mi gimnasio ');

      expect(result.needsName, isFalse);
      expect(result.name, 'Mi gimnasio');
      final data =
          (await firestore.collection('gyms').doc('ChIJ_place_9').get())
              .data()!;
      expect(data['name'], 'Mi gimnasio');
      expect(data['nameNeeded'], isFalse);
      verifyNever(() => mockClient.get(any(), headers: any(named: 'headers')));
    });

    test('a blocked name is rejected by moderation and never written',
        () async {
      await firestore.collection('gyms').doc('ChIJ_place_9').set({
        'name': 'Marcador',
        'nameNeeded': true,
        'lat': -34.5,
        'lng': -58.4,
        'geohash': '6d6m7',
        'source': 'google-places',
        'createdAt': Timestamp.fromDate(DateTime.utc(2026, 1, 1)),
      });

      await expectLater(
        () => sut.call(placeId: 'ChIJ_place_9', name: 'puta madre'),
        throwsA(isA<ModerationBlockedException>()),
      );
      final data =
          (await firestore.collection('gyms').doc('ChIJ_place_9').get())
              .data()!;
      expect(data['name'], 'Marcador');
    });
  });

  group('ResolveGymPlaceService.call — cache miss', () {
    test('without a typed name it asks for it and never calls Google',
        () async {
      final result = await sut.call(placeId: 'ChIJ_place_2');

      expect(result.needsName, isTrue);
      verifyNever(() => mockClient.get(any(), headers: any(named: 'headers')));
      expect(
          (await firestore.collection('gyms').doc('ChIJ_place_2').get()).exists,
          isFalse);
    });

    test('GETs Place Details (New) asking ONLY for location', () async {
      when(() => mockClient.get(any(), headers: any(named: 'headers')))
          .thenAnswer((_) async => okResponse(detailsBody()));

      await sut.call(placeId: 'ChIJ_place_2', name: 'Mi gym');

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
      expect(headers['X-Goog-FieldMask'], 'location');
    });

    test('appends sessionToken as a query param when provided', () async {
      when(() => mockClient.get(any(), headers: any(named: 'headers')))
          .thenAnswer((_) async => okResponse(detailsBody()));

      await sut.call(
        placeId: 'ChIJ_place_2',
        name: 'Mi gym',
        sessionToken: 'tok-1',
      );

      final captured = verify(() =>
              mockClient.get(captureAny(), headers: any(named: 'headers')))
          .captured;
      final uri = captured.single as Uri;
      expect(uri.queryParameters['sessionToken'], 'tok-1');
    });

    test('stores the typed name + coords, and NO Google text', () async {
      when(() => mockClient.get(any(), headers: any(named: 'headers')))
          .thenAnswer((_) async => okResponse(detailsBody()));

      final result =
          await sut.call(placeId: 'ChIJ_place_3', name: ' SmartFit Cabal ');

      expect(result.gymId, 'ChIJ_place_3');
      expect(result.name, 'SmartFit Cabal');
      expect(result.needsName, isFalse);
      expect(result.source, 'google-places');

      final raw = (await firestore.collection('gyms').doc('ChIJ_place_3').get())
          .data()!;
      expect(raw['name'], 'SmartFit Cabal');
      expect(raw.containsKey('address'), isFalse);
      expect(raw['lat'], -34.61);
      expect(raw['lng'], -58.44);
      expect(raw['geohash'], isNotEmpty);
      expect(raw['coordsFetchedAt'], isNotNull);
      expect(raw['placeStatus'], 'ok');
      expect(raw.toString(), isNot(contains('Google')));

      final stored = await gymRepository.getById('ChIJ_place_3');
      expect(stored!.source, GymSource.googlePlaces);
      expect(stored.coordsFetchedAt, isNotNull);
    });

    test('a blocked name is rejected before any http call', () async {
      await expectLater(
        () => sut.call(placeId: 'ChIJ_place_2', name: 'puta madre'),
        throwsA(isA<ModerationBlockedException>()),
      );
      verifyNever(() => mockClient.get(any(), headers: any(named: 'headers')));
    });

    test('second call for the same placeId hits the cache, not http', () async {
      when(() => mockClient.get(any(), headers: any(named: 'headers')))
          .thenAnswer((_) async => okResponse(detailsBody()));

      await sut.call(placeId: 'ChIJ_place_4', name: 'Cacheado Gym');
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
        () => noKeySut.call(placeId: 'ChIJ_place_5', name: 'Mi gym'),
        throwsA(isA<ResolveGymPlaceFailure>()),
      );
      verifyNever(() => mockClient.get(any(), headers: any(named: 'headers')));
    });

    test('non-200 response throws ResolveGymPlaceFailure, never leaks key',
        () async {
      when(() => mockClient.get(any(), headers: any(named: 'headers')))
          .thenAnswer((_) async => http.Response('server error', 500));

      await expectLater(
        () => sut.call(placeId: 'ChIJ_place_6', name: 'Mi gym'),
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
        () => sut.call(placeId: 'ChIJ_place_7', name: 'Mi gym'),
        throwsA(isA<ResolveGymPlaceFailure>()),
      );
    });

    test('incomplete Places response (missing location) throws', () async {
      when(() => mockClient.get(any(), headers: any(named: 'headers')))
          .thenAnswer((_) async => okResponse({
                'id': 'ChIJ_place_8',
              }));

      await expectLater(
        () => sut.call(placeId: 'ChIJ_place_8', name: 'Mi gym'),
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
