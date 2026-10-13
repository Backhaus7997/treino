// Plan B — resolución CLIENT-SIDE de un Place (el CF no se puede desplegar).
//   1. Read-through cache vía GymRepository.getById(placeId).
//   2. En miss: GET Place Details (New) pidiendo SOLO `location`, y se crea
//      gyms/{placeId} con el marcador de nombre (Google no deja guardar su
//      texto: #1338). Nadie tipea el nombre.
//   3. El nombre de Google se pide EN VIVO con fetchDisplayName y no se guarda.
//   4. Los errores no crashean — salen como ResolveGymPlaceFailure.
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:treino/features/gyms/data/gym_repository.dart';
import 'package:treino/features/gyms/data/resolve_gym_place_service.dart';
import 'package:treino/features/gyms/domain/gym.dart';
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
      verifyNever(() => mockClient.get(any(), headers: any(named: 'headers')));
    });

    test(
        'a legacy nameNeeded gym is returned as-is: nobody is asked for a name',
        () async {
      await firestore.collection('gyms').doc('ChIJ_place_1').set({
        'name': 'Gimnasio',
        'nameNeeded': true,
        'lat': -34.5598,
        'lng': -58.4615,
        'geohash': '6d6m7',
        'source': 'google-places',
        'createdAt': Timestamp.fromDate(DateTime.utc(2026, 1, 1)),
      });

      final result = await sut.call(placeId: 'ChIJ_place_1');

      expect(result.gymId, 'ChIJ_place_1');
      final doc = await firestore.collection('gyms').doc('ChIJ_place_1').get();
      expect(doc.data()!['nameNeeded'], isTrue);
      verifyNever(() => mockClient.get(any(), headers: any(named: 'headers')));
    });
  });

  group('ResolveGymPlaceService.call — cache miss', () {
    test('GETs Place Details (New) asking ONLY for location', () async {
      when(() => mockClient.get(any(), headers: any(named: 'headers')))
          .thenAnswer((_) async => okResponse(detailsBody()));

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
      expect(headers['X-Goog-FieldMask'], 'location');
    });

    test('appends sessionToken as a query param when provided', () async {
      when(() => mockClient.get(any(), headers: any(named: 'headers')))
          .thenAnswer((_) async => okResponse(detailsBody()));

      await sut.call(placeId: 'ChIJ_place_2', sessionToken: 'tok-1');

      final captured = verify(() =>
              mockClient.get(captureAny(), headers: any(named: 'headers')))
          .captured;
      final uri = captured.single as Uri;
      expect(uri.queryParameters['sessionToken'], 'tok-1');
    });

    test('creates the gym with the placeholder name + coords, NO Google text',
        () async {
      when(() => mockClient.get(any(), headers: any(named: 'headers')))
          .thenAnswer((_) async => okResponse(detailsBody()));

      final result = await sut.call(placeId: 'ChIJ_place_3');

      expect(result.gymId, 'ChIJ_place_3');
      expect(result.name, kGymPlaceholderName);
      expect(result.source, 'google-places');

      final raw = (await firestore.collection('gyms').doc('ChIJ_place_3').get())
          .data()!;
      expect(raw['name'], kGymPlaceholderName);
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

    test('second call for the same placeId hits the cache, not http', () async {
      when(() => mockClient.get(any(), headers: any(named: 'headers')))
          .thenAnswer((_) async => okResponse(detailsBody()));

      await sut.call(placeId: 'ChIJ_place_4');
      await sut.call(placeId: 'ChIJ_place_4');

      verify(() => mockClient.get(any(), headers: any(named: 'headers')))
          .called(1);
    });
  });

  group('ResolveGymPlaceService.fetchDisplayName (en vivo, sin guardar)', () {
    test('asks ONLY for displayName and returns its text', () async {
      when(() => mockClient.get(any(), headers: any(named: 'headers')))
          .thenAnswer((_) async => okResponse(detailsBody()));

      final name = await sut.fetchDisplayName('ChIJ_place_2');

      expect(name, 'Texto de Google que NO se guarda');
      final captured = verify(() => mockClient.get(
            captureAny(),
            headers: captureAny(named: 'headers'),
          )).captured;
      final headers = captured[1] as Map<String, String>;
      expect(headers['X-Goog-FieldMask'], 'displayName');
    });

    test('never writes anything to Firestore', () async {
      when(() => mockClient.get(any(), headers: any(named: 'headers')))
          .thenAnswer((_) async => okResponse(detailsBody()));

      await sut.fetchDisplayName('ChIJ_place_2');

      final snap = await firestore.collection('gyms').get();
      expect(snap.docs, isEmpty);
    });

    test('missing or blank displayName -> null', () async {
      when(() => mockClient.get(any(), headers: any(named: 'headers')))
          .thenAnswer((_) async => okResponse({
                'displayName': {'text': '   '},
              }));
      expect(await sut.fetchDisplayName('ChIJ_x'), isNull);

      when(() => mockClient.get(any(), headers: any(named: 'headers')))
          .thenAnswer((_) async => okResponse(<String, dynamic>{}));
      expect(await sut.fetchDisplayName('ChIJ_x'), isNull);
    });

    test('non-200 throws ResolveGymPlaceFailure', () async {
      when(() => mockClient.get(any(), headers: any(named: 'headers')))
          .thenAnswer((_) async => http.Response('nope', 403));

      await expectLater(
        () => sut.fetchDisplayName('ChIJ_x'),
        throwsA(isA<ResolveGymPlaceFailure>()),
      );
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
          .thenAnswer((_) async => okResponse({'id': 'ChIJ_place_8'}));

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
