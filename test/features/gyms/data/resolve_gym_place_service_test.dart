// T2.10 RED — gym-google-places Phase 2.
//
// Thin wrapper around the `resolveGymPlace` Cloud Function, mirroring
// AccountDeletionService's shape (functions region southamerica-east1;
// cloud client default is us-central1, MUST override).
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/features/gyms/data/resolve_gym_place_service.dart';

class MockFirebaseFunctions extends Mock implements FirebaseFunctions {}

class MockHttpsCallable extends Mock implements HttpsCallable {}

class MockHttpsCallableResult extends Mock
    implements HttpsCallableResult<Map<String, dynamic>> {}

void main() {
  setUpAll(() {
    registerFallbackValue(<String, dynamic>{});
  });

  late MockFirebaseFunctions mockFunctions;
  late MockHttpsCallable mockCallable;
  late MockHttpsCallableResult mockResult;
  late ResolveGymPlaceService sut;

  setUp(() {
    mockFunctions = MockFirebaseFunctions();
    mockCallable = MockHttpsCallable();
    mockResult = MockHttpsCallableResult();

    when(() => mockFunctions.httpsCallable('resolveGymPlace'))
        .thenReturn(mockCallable);

    sut = ResolveGymPlaceService(functions: mockFunctions);
  });

  group('ResolveGymPlaceService.call', () {
    test(
        'calls resolveGymPlace with placeId and sessionToken, returns '
        'ResolveGymPlaceResult', () async {
      when(() => mockCallable.call<Map<String, dynamic>>(any()))
          .thenAnswer((_) async {
        when(() => mockResult.data).thenReturn({
          'gymId': 'ChIJ_place_1',
          'name': 'SportClub Belgrano',
          'address': 'Cabildo 1789, CABA',
          'source': 'google-places',
        });
        return mockResult;
      });

      final result = await sut.call(
        placeId: 'ChIJ_place_1',
        sessionToken: 'tok-1',
      );

      verify(() => mockCallable.call<Map<String, dynamic>>({
            'placeId': 'ChIJ_place_1',
            'sessionToken': 'tok-1',
          })).called(1);
      expect(result.gymId, 'ChIJ_place_1');
      expect(result.name, 'SportClub Belgrano');
    });

    test('sessionToken is optional', () async {
      when(() => mockCallable.call<Map<String, dynamic>>(any()))
          .thenAnswer((_) async {
        when(() => mockResult.data).thenReturn({
          'gymId': 'ChIJ_place_1',
          'name': 'SportClub Belgrano',
          'address': null,
          'source': 'google-places',
        });
        return mockResult;
      });

      await sut.call(placeId: 'ChIJ_place_1');

      verify(() => mockCallable.call<Map<String, dynamic>>({
            'placeId': 'ChIJ_place_1',
          })).called(1);
    });

    test('FirebaseFunctionsException propagates as ResolveGymPlaceFailure',
        () async {
      when(() => mockCallable.call<Map<String, dynamic>>(any())).thenThrow(
        FirebaseFunctionsException(
          code: 'invalid-argument',
          message: 'placeId is required',
          details: null,
        ),
      );

      await expectLater(
        () => sut.call(placeId: ''),
        throwsA(isA<ResolveGymPlaceFailure>()),
      );
    });

    test('unknown error propagates as ResolveGymPlaceFailure', () async {
      when(() => mockCallable.call<Map<String, dynamic>>(any()))
          .thenThrow(Exception('network error'));

      await expectLater(
        () => sut.call(placeId: 'ChIJ_place_1'),
        throwsA(isA<ResolveGymPlaceFailure>()),
      );
    });
  });
}
