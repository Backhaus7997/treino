// T36 RED — SCENARIO-561, SCENARIO-562, SCENARIO-563
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/features/profile/data/account_deletion_service.dart';

// --- Mocks ---
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
  late AccountDeletionService sut;

  setUp(() {
    mockFunctions = MockFirebaseFunctions();
    mockCallable = MockHttpsCallable();
    mockResult = MockHttpsCallableResult();

    when(() => mockFunctions.httpsCallable('deleteAccount'))
        .thenReturn(mockCallable);

    sut = AccountDeletionService(functions: mockFunctions);
  });

  // SCENARIO-561
  group('AccountDeletionService.call', () {
    test(
        'SCENARIO-561: calls deleteAccount callable with uid and returns '
        'DeletionResult.success on status=success', () async {
      when(() => mockCallable.call<Map<String, dynamic>>(any())).thenAnswer(
        (_) async {
          when(() => mockResult.data).thenReturn({
            'status': 'success',
            'deletedCollections': ['users', 'friendships'],
            'errors': <dynamic>[],
          });
          return mockResult;
        },
      );

      final result = await sut.call(uid: 'uid-test');

      verify(() => mockCallable.call<Map<String, dynamic>>({'uid': 'uid-test'}))
          .called(1);
      expect(result.status, equals('success'));
    });

    test(
        'SCENARIO-561: status=partial is parsed to DeletionResult.partial', () async {
      when(() => mockCallable.call<Map<String, dynamic>>(any())).thenAnswer(
        (_) async {
          when(() => mockResult.data).thenReturn({
            'status': 'partial',
            'deletedCollections': ['users'],
            'errors': [
              {'step': 'storage', 'code': 'not-found', 'message': 'no avatar'}
            ],
          });
          return mockResult;
        },
      );

      final result = await sut.call(uid: 'uid-test');

      expect(result.status, equals('partial'));
    });

    // SCENARIO-562
    test(
        'SCENARIO-562: FirebaseFunctionsException propagates as AccountDeletionFailure.serverError',
        () async {
      when(() => mockCallable.call<Map<String, dynamic>>(any())).thenThrow(
        FirebaseFunctionsException(
          code: 'permission-denied',
          message: 'uid mismatch',
          details: null,
        ),
      );

      await expectLater(
        () => sut.call(uid: 'uid-test'),
        throwsA(isA<AccountDeletionFailure>()),
      );
    });

    // SCENARIO-563
    test('SCENARIO-563: unknown error propagates as AccountDeletionFailure',
        () async {
      when(() => mockCallable.call<Map<String, dynamic>>(any()))
          .thenThrow(Exception('network error'));

      await expectLater(
        () => sut.call(uid: 'uid-test'),
        throwsA(isA<AccountDeletionFailure>()),
      );
    });
  });
}
