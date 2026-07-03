// Task 3.1 RED / 3.2 GREEN — gym-selection-v2 Phase 3 (addendum, AD-12).
//
// PlacesTextSearchService talks to Places API (New) Text Search:
//   POST https://places.googleapis.com/v1/places:searchText
//   Headers: X-Goog-Api-Key, X-Goog-FieldMask, Content-Type: application/json
//   Body: { textQuery, pageSize, locationBias?: { circle: { center, radius } } }
//   Response: places[].{id, displayName, formattedAddress}
//
// Mirrors places_nearby_search_service_test.dart's fake-http.Client pattern
// and error-split conventions (design AD-12). Maps to the EXISTING
// GymSuggestion DTO — no new domain type needed (unlike NearbyGym/AD-8).
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:treino/features/gyms/data/places_text_search_service.dart';
import 'package:treino/features/gyms/domain/gym_suggestion.dart';

class MockHttpClient extends Mock implements http.Client {}

void main() {
  setUpAll(() {
    registerFallbackValue(Uri.parse('https://example.com'));
  });

  late MockHttpClient mockClient;
  late PlacesTextSearchService sut;

  http.Response okResponse(Map<String, dynamic> body) =>
      http.Response(jsonEncode(body), 200);

  setUp(() {
    mockClient = MockHttpClient();
    sut = PlacesTextSearchService(
      httpClient: mockClient,
      clientApiKey: 'test-client-key',
    );
  });

  group('PlacesTextSearchService.search', () {
    test('empty API key surfaces a clear error, never calls http', () async {
      final noKeySut = PlacesTextSearchService(
        httpClient: mockClient,
        clientApiKey: '',
      );

      await expectLater(
        () => noKeySut.search(textQuery: 'qivox'),
        throwsA(isA<PlacesTextSearchConfigError>()),
      );

      verifyNever(() => mockClient.post(any(),
          headers: any(named: 'headers'), body: any(named: 'body')));
    });

    test('POSTs to the searchText (New) endpoint with the expected headers',
        () async {
      when(() => mockClient.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          )).thenAnswer((_) async => okResponse({'places': []}));

      await sut.search(textQuery: 'qivox');

      final captured = verify(() => mockClient.post(
            captureAny(),
            headers: captureAny(named: 'headers'),
            body: any(named: 'body'),
          )).captured;

      final uri = captured[0] as Uri;
      final headers = captured[1] as Map<String, String>;

      expect(
        uri.toString(),
        'https://places.googleapis.com/v1/places:searchText',
      );
      expect(headers['X-Goog-Api-Key'], 'test-client-key');
      expect(
        headers['X-Goog-FieldMask'],
        'places.id,places.displayName,places.formattedAddress',
      );
      expect(headers['Content-Type'], 'application/json');
    });

    test(
        'request body includes textQuery/pageSize and biases when given a '
        'location', () async {
      when(() => mockClient.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          )).thenAnswer((_) async => okResponse({'places': []}));

      await sut.search(
        textQuery: 'qivox',
        biasLatitude: -34.5598,
        biasLongitude: -58.4615,
      );

      final captured = verify(() => mockClient.post(
            any(),
            headers: any(named: 'headers'),
            body: captureAny(named: 'body'),
          )).captured;

      final body = jsonDecode(captured.single as String) as Map;
      expect(body['textQuery'], 'qivox');
      expect(body['pageSize'], 20);

      final bias = body['locationBias'] as Map;
      final circle = bias['circle'] as Map;
      final center = circle['center'] as Map;
      expect(center['latitude'], -34.5598);
      expect(center['longitude'], -58.4615);
      expect(circle['radius'], isNotNull);
    });

    test(
        'request body omits locationBias entirely when no location is given '
        '(mirrors Autocomplete\'s conditional-inclusion contract)', () async {
      when(() => mockClient.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          )).thenAnswer((_) async => okResponse({'places': []}));

      await sut.search(textQuery: 'qivox');

      final captured = verify(() => mockClient.post(
            any(),
            headers: any(named: 'headers'),
            body: captureAny(named: 'body'),
          )).captured;

      final body = jsonDecode(captured.single as String) as Map;
      expect(body.containsKey('locationBias'), isFalse);
    });

    test('parses places[] into a GymSuggestion list', () async {
      when(() => mockClient.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          )).thenAnswer((_) async => okResponse({
            'places': [
              {
                'id': 'ChIJ_1',
                'displayName': {'text': 'QIVOX Villa Warcalde'},
                'formattedAddress': 'Some street 123, Córdoba',
              },
              {
                'id': 'ChIJ_2',
                'displayName': {'text': 'QIVOX Nueva Córdoba'},
              },
            ],
          }));

      final result = await sut.search(textQuery: 'qivox');

      expect(result, hasLength(2));
      expect(result[0], isA<GymSuggestion>());
      expect(result[0].placeId, 'ChIJ_1');
      expect(result[0].primaryText, 'QIVOX Villa Warcalde');
      expect(result[0].secondaryText, 'Some street 123, Córdoba');
      expect(result[1].placeId, 'ChIJ_2');
      expect(result[1].secondaryText, isNull);
    });

    test('empty places array returns const [], not an error', () async {
      when(() => mockClient.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          )).thenAnswer((_) async => okResponse({'places': []}));

      final result = await sut.search(textQuery: 'qivox');

      expect(result, isEmpty);
    });

    test('response with no places key returns empty list', () async {
      when(() => mockClient.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          )).thenAnswer((_) async => okResponse({}));

      final result = await sut.search(textQuery: 'qivox');

      expect(result, isEmpty);
    });

    test('non-200 response throws PlacesTextSearchError, never leaks key',
        () async {
      when(() => mockClient.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          )).thenAnswer((_) async => http.Response('server error', 500));

      await expectLater(
        () => sut.search(textQuery: 'qivox'),
        throwsA(
          predicate<PlacesTextSearchError>(
            (e) =>
                e.statusCode == 500 &&
                !e.toString().contains('test-client-key'),
          ),
        ),
      );
    });

    test(
        'network exception propagates as PlacesTextSearchError, '
        'never leaks key', () async {
      when(() => mockClient.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          )).thenThrow(Exception('socket closed'));

      await expectLater(
        () => sut.search(textQuery: 'qivox'),
        throwsA(
          predicate<PlacesTextSearchError>(
            (e) => !e.toString().contains('test-client-key'),
          ),
        ),
      );
    });

    test('config error message never leaks the (empty) key either', () async {
      final noKeySut = PlacesTextSearchService(
        httpClient: mockClient,
        clientApiKey: '',
      );

      try {
        await noKeySut.search(textQuery: 'qivox');
        fail('expected PlacesTextSearchConfigError');
      } on PlacesTextSearchConfigError catch (e) {
        expect(e.toString().contains('test-client-key'), isFalse);
      }
    });
  });
}
