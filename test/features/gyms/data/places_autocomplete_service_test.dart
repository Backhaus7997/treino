// T2.8 RED — gym-google-places Phase 2.
//
// PlacesAutocompleteService talks to Places API (New) Autocomplete:
//   POST https://places.googleapis.com/v1/places:autocomplete
//   Headers: X-Goog-Api-Key, Content-Type: application/json
//   Body: { input, sessionToken, locationBias?, includedPrimaryTypes }
//   Response: suggestions[].placePrediction.{placeId, structuredFormat...}
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:treino/features/gyms/data/places_autocomplete_service.dart';
import 'package:treino/features/gyms/domain/gym_suggestion.dart';

class MockHttpClient extends Mock implements http.Client {}

void main() {
  setUpAll(() {
    registerFallbackValue(Uri.parse('https://example.com'));
  });

  late MockHttpClient mockClient;
  late PlacesAutocompleteService sut;

  http.Response okResponse(Map<String, dynamic> body) =>
      http.Response(jsonEncode(body), 200);

  setUp(() {
    mockClient = MockHttpClient();
    sut = PlacesAutocompleteService(
      httpClient: mockClient,
      clientApiKey: 'test-client-key',
    );
  });

  group('PlacesAutocompleteService.search', () {
    test('empty API key surfaces a clear error, never calls http', () async {
      final noKeySut = PlacesAutocompleteService(
        httpClient: mockClient,
        clientApiKey: '',
      );

      await expectLater(
        () => noKeySut.search(query: 'sport', sessionToken: 'tok-1'),
        throwsA(isA<PlacesAutocompleteConfigError>()),
      );

      verifyNever(() => mockClient.post(any(),
          headers: any(named: 'headers'), body: any(named: 'body')));
    });

    test('empty query returns empty list without calling http', () async {
      final result = await sut.search(query: '   ', sessionToken: 'tok-1');

      expect(result, isEmpty);
      verifyNever(() => mockClient.post(any(),
          headers: any(named: 'headers'), body: any(named: 'body')));
    });

    test('POSTs to the Autocomplete (New) endpoint with the expected headers',
        () async {
      when(() => mockClient.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          )).thenAnswer((_) async => okResponse({'suggestions': []}));

      await sut.search(query: 'sportclub', sessionToken: 'tok-1');

      final captured = verify(() => mockClient.post(
            captureAny(),
            headers: captureAny(named: 'headers'),
            body: any(named: 'body'),
          )).captured;

      final uri = captured[0] as Uri;
      final headers = captured[1] as Map<String, String>;

      expect(
        uri.toString(),
        'https://places.googleapis.com/v1/places:autocomplete',
      );
      expect(headers['X-Goog-Api-Key'], 'test-client-key');
      expect(headers['Content-Type'], 'application/json');
    });

    test('request body includes input/sessionToken/includedPrimaryTypes',
        () async {
      when(() => mockClient.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          )).thenAnswer((_) async => okResponse({'suggestions': []}));

      await sut.search(query: 'sportclub', sessionToken: 'tok-1');

      final captured = verify(() => mockClient.post(
            any(),
            headers: any(named: 'headers'),
            body: captureAny(named: 'body'),
          )).captured;

      final body = jsonDecode(captured.single as String) as Map;
      expect(body['input'], 'sportclub');
      expect(body['sessionToken'], 'tok-1');
      expect(body['includedPrimaryTypes'], ['gym']);
      expect(body.containsKey('locationBias'), isFalse);
    });

    test('includes locationBias circle when a position is provided', () async {
      when(() => mockClient.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          )).thenAnswer((_) async => okResponse({'suggestions': []}));

      await sut.search(
        query: 'sportclub',
        sessionToken: 'tok-1',
        biasLatitude: -34.5598,
        biasLongitude: -58.4615,
        biasRadiusMeters: 30000,
      );

      final captured = verify(() => mockClient.post(
            any(),
            headers: any(named: 'headers'),
            body: captureAny(named: 'body'),
          )).captured;

      final body = jsonDecode(captured.single as String) as Map;
      final bias = body['locationBias'] as Map;
      final circle = bias['circle'] as Map;
      final center = circle['center'] as Map;
      expect(center['latitude'], -34.5598);
      expect(center['longitude'], -58.4615);
      expect(circle['radius'], 30000);
    });

    test(
        'omits locationBias when no position is provided (no-permission '
        'fallback)', () async {
      when(() => mockClient.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          )).thenAnswer((_) async => okResponse({'suggestions': []}));

      await sut.search(query: 'sportclub', sessionToken: 'tok-1');

      final captured = verify(() => mockClient.post(
            any(),
            headers: any(named: 'headers'),
            body: captureAny(named: 'body'),
          )).captured;

      final body = jsonDecode(captured.single as String) as Map;
      expect(body.containsKey('locationBias'), isFalse);
    });

    test('parses suggestions.placePrediction into GymSuggestion list',
        () async {
      when(() => mockClient.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          )).thenAnswer((_) async => okResponse({
            'suggestions': [
              {
                'placePrediction': {
                  'placeId': 'ChIJ_1',
                  'text': {'text': 'SportClub Belgrano, Cabildo 1789'},
                  'structuredFormat': {
                    'mainText': {'text': 'SportClub Belgrano'},
                    'secondaryText': {'text': 'Cabildo 1789, CABA'},
                  },
                },
              },
              {
                'placePrediction': {
                  'placeId': 'ChIJ_2',
                  'text': {'text': 'Megatlon Recoleta'},
                  'structuredFormat': {
                    'mainText': {'text': 'Megatlon Recoleta'},
                  },
                },
              },
            ],
          }));

      final result = await sut.search(query: 'sport', sessionToken: 'tok-1');

      expect(result, hasLength(2));
      expect(result[0], isA<GymSuggestion>());
      expect(result[0].placeId, 'ChIJ_1');
      expect(result[0].primaryText, 'SportClub Belgrano');
      expect(result[0].secondaryText, 'Cabildo 1789, CABA');
      expect(result[1].placeId, 'ChIJ_2');
      expect(result[1].secondaryText, isNull);
    });

    test('response with no suggestions key returns empty list', () async {
      when(() => mockClient.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          )).thenAnswer((_) async => okResponse({}));

      final result = await sut.search(query: 'sport', sessionToken: 'tok-1');

      expect(result, isEmpty);
    });

    test('non-200 response throws PlacesAutocompleteError, never leaks key',
        () async {
      when(() => mockClient.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          )).thenAnswer((_) async => http.Response('server error', 500));

      await expectLater(
        () => sut.search(query: 'sport', sessionToken: 'tok-1'),
        throwsA(
          predicate<PlacesAutocompleteError>(
            (e) => !e.toString().contains('test-client-key'),
          ),
        ),
      );
    });

    test('network exception propagates as PlacesAutocompleteError', () async {
      when(() => mockClient.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          )).thenThrow(Exception('socket closed'));

      await expectLater(
        () => sut.search(query: 'sport', sessionToken: 'tok-1'),
        throwsA(isA<PlacesAutocompleteError>()),
      );
    });
  });

  group('PlacesAutocompleteService.newSessionToken', () {
    test('generates a non-empty token', () {
      final token = sut.newSessionToken();
      expect(token, isNotEmpty);
    });

    test('generates different tokens across calls', () {
      final a = sut.newSessionToken();
      final b = sut.newSessionToken();
      expect(a, isNot(equals(b)));
    });
  });
}
