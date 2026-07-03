// Task 1.3 RED / 1.4 GREEN — gym-selection-v2 Phase 1.
//
// PlacesNearbySearchService talks to Places API (New) searchNearby:
//   POST https://places.googleapis.com/v1/places:searchNearby
//   Headers: X-Goog-Api-Key, X-Goog-FieldMask, Content-Type: application/json
//   Body: { includedTypes: ['gym'], maxResultCount, rankPreference: 'DISTANCE',
//           locationRestriction: { circle: { center, radius } } }
//   Response: places[].{id, displayName, formattedAddress, location}
//
// Mirrors places_autocomplete_service_test.dart's fake-http.Client pattern
// and error-split conventions (design AD-6/AD-7).
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:treino/features/gyms/data/places_nearby_search_service.dart';
import 'package:treino/features/gyms/domain/nearby_gym.dart';

class MockHttpClient extends Mock implements http.Client {}

void main() {
  setUpAll(() {
    registerFallbackValue(Uri.parse('https://example.com'));
  });

  late MockHttpClient mockClient;
  late PlacesNearbySearchService sut;

  http.Response okResponse(Map<String, dynamic> body) =>
      http.Response(jsonEncode(body), 200);

  setUp(() {
    mockClient = MockHttpClient();
    sut = PlacesNearbySearchService(
      httpClient: mockClient,
      clientApiKey: 'test-client-key',
    );
  });

  group('PlacesNearbySearchService.search', () {
    test('empty API key surfaces a clear error, never calls http', () async {
      final noKeySut = PlacesNearbySearchService(
        httpClient: mockClient,
        clientApiKey: '',
      );

      await expectLater(
        () => noKeySut.search(latitude: -34.5598, longitude: -58.4615),
        throwsA(isA<PlacesNearbySearchConfigError>()),
      );

      verifyNever(() => mockClient.post(any(),
          headers: any(named: 'headers'), body: any(named: 'body')));
    });

    test('POSTs to the searchNearby (New) endpoint with the expected headers',
        () async {
      when(() => mockClient.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          )).thenAnswer((_) async => okResponse({'places': []}));

      await sut.search(latitude: -34.5598, longitude: -58.4615);

      final captured = verify(() => mockClient.post(
            captureAny(),
            headers: captureAny(named: 'headers'),
            body: any(named: 'body'),
          )).captured;

      final uri = captured[0] as Uri;
      final headers = captured[1] as Map<String, String>;

      expect(
        uri.toString(),
        'https://places.googleapis.com/v1/places:searchNearby',
      );
      expect(headers['X-Goog-Api-Key'], 'test-client-key');
      expect(
        headers['X-Goog-FieldMask'],
        'places.id,places.displayName,places.formattedAddress,places.location',
      );
      expect(headers['Content-Type'], 'application/json');
    });

    test(
        'request body includes includedTypes/rankPreference/radius/'
        'maxResultCount/center', () async {
      when(() => mockClient.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          )).thenAnswer((_) async => okResponse({'places': []}));

      await sut.search(latitude: -34.5598, longitude: -58.4615);

      final captured = verify(() => mockClient.post(
            any(),
            headers: any(named: 'headers'),
            body: captureAny(named: 'body'),
          )).captured;

      final body = jsonDecode(captured.single as String) as Map;
      expect(body['includedTypes'], ['gym']);
      expect(body['rankPreference'], 'DISTANCE');
      expect(body['maxResultCount'], 20);

      final restriction = body['locationRestriction'] as Map;
      final circle = restriction['circle'] as Map;
      final center = circle['center'] as Map;
      expect(center['latitude'], -34.5598);
      expect(center['longitude'], -58.4615);
      expect(circle['radius'], 5000);
    });

    test('custom radiusMeters/maxResultCount are forwarded in the body',
        () async {
      when(() => mockClient.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          )).thenAnswer((_) async => okResponse({'places': []}));

      await sut.search(
        latitude: -34.5598,
        longitude: -58.4615,
        radiusMeters: 3000,
        maxResultCount: 10,
      );

      final captured = verify(() => mockClient.post(
            any(),
            headers: any(named: 'headers'),
            body: captureAny(named: 'body'),
          )).captured;

      final body = jsonDecode(captured.single as String) as Map;
      expect(body['maxResultCount'], 10);
      final restriction = body['locationRestriction'] as Map;
      final circle = restriction['circle'] as Map;
      expect(circle['radius'], 3000);
    });

    test('parses places[] into a NearbyGym list', () async {
      when(() => mockClient.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          )).thenAnswer((_) async => okResponse({
            'places': [
              {
                'id': 'ChIJ_1',
                'displayName': {'text': 'SportClub Belgrano'},
                'formattedAddress': 'Cabildo 1789, CABA',
                'location': {'latitude': -34.5598, 'longitude': -58.4615},
              },
              {
                'id': 'ChIJ_2',
                'displayName': {'text': 'Megatlon Recoleta'},
                'location': {'latitude': -34.59, 'longitude': -58.39},
              },
            ],
          }));

      final result = await sut.search(latitude: -34.5598, longitude: -58.4615);

      expect(result, hasLength(2));
      expect(result[0], isA<NearbyGym>());
      expect(result[0].placeId, 'ChIJ_1');
      expect(result[0].name, 'SportClub Belgrano');
      expect(result[0].address, 'Cabildo 1789, CABA');
      expect(result[0].lat, -34.5598);
      expect(result[0].lng, -58.4615);
      expect(result[1].placeId, 'ChIJ_2');
      expect(result[1].address, isNull);
    });

    test('empty places array returns const [], not an error', () async {
      when(() => mockClient.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          )).thenAnswer((_) async => okResponse({'places': []}));

      final result = await sut.search(latitude: -34.5598, longitude: -58.4615);

      expect(result, isEmpty);
    });

    test('response with no places key returns empty list', () async {
      when(() => mockClient.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          )).thenAnswer((_) async => okResponse({}));

      final result = await sut.search(latitude: -34.5598, longitude: -58.4615);

      expect(result, isEmpty);
    });

    test('non-200 response throws PlacesNearbySearchError, never leaks key',
        () async {
      when(() => mockClient.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          )).thenAnswer((_) async => http.Response('server error', 500));

      await expectLater(
        () => sut.search(latitude: -34.5598, longitude: -58.4615),
        throwsA(
          predicate<PlacesNearbySearchError>(
            (e) =>
                e.statusCode == 500 &&
                !e.toString().contains('test-client-key'),
          ),
        ),
      );
    });

    test(
        'network exception propagates as PlacesNearbySearchError, '
        'never leaks key', () async {
      when(() => mockClient.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          )).thenThrow(Exception('socket closed'));

      await expectLater(
        () => sut.search(latitude: -34.5598, longitude: -58.4615),
        throwsA(
          predicate<PlacesNearbySearchError>(
            (e) => !e.toString().contains('test-client-key'),
          ),
        ),
      );
    });

    test('config error message never leaks the (empty) key either', () async {
      final noKeySut = PlacesNearbySearchService(
        httpClient: mockClient,
        clientApiKey: '',
      );

      try {
        await noKeySut.search(latitude: -34.5598, longitude: -58.4615);
        fail('expected PlacesNearbySearchConfigError');
      } on PlacesNearbySearchConfigError catch (e) {
        expect(e.toString().contains('test-client-key'), isFalse);
      }
    });
  });
}
