// RED — Fase 7 PR4 slice 2: acceptTrainerLink callable client wrapper.
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/features/coach/data/trainer_link_promotion_service.dart';
import 'package:treino/features/coach/domain/subscription_tier.dart';

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
  late TrainerLinkPromotionService sut;

  setUp(() {
    mockFunctions = MockFirebaseFunctions();
    mockCallable = MockHttpsCallable();
    mockResult = MockHttpsCallableResult();

    when(() => mockFunctions.httpsCallable('acceptTrainerLink'))
        .thenReturn(mockCallable);

    sut = TrainerLinkPromotionService(functions: mockFunctions);
  });

  group('TrainerLinkPromotionService.accept — success', () {
    test('calls acceptTrainerLink callable with {linkId} and returns void',
        () async {
      when(() => mockCallable.call<Map<String, dynamic>>(any()))
          .thenAnswer((_) async {
        when(() => mockResult.data)
            .thenReturn({'status': 'ok', 'weightedLoad': 3, 'limit': 7});
        return mockResult;
      });

      await sut.accept('link-1');

      verify(() =>
              mockCallable.call<Map<String, dynamic>>({'linkId': 'link-1'}))
          .called(1);
    });
  });

  group('TrainerLinkPromotionService.accept — resource-exhausted', () {
    test(
        'well-formed Map<String, dynamic> details parses to '
        'LinkPromotionFailure\$PlanLimitReached', () async {
      when(() => mockCallable.call<Map<String, dynamic>>(any())).thenThrow(
        FirebaseFunctionsException(
          code: 'resource-exhausted',
          message: 'Weighted-load limit reached.',
          details: const <String, dynamic>{
            'reason': 'plan-limit',
            'tier': 'plan1',
            'limit': 7,
            'currentLoad': 6.5,
            'projectedLoad': 7.5,
          },
        ),
      );

      try {
        await sut.accept('link-1');
        fail('expected LinkPromotionFailure\$PlanLimitReached');
      } on LinkPromotionFailure$PlanLimitReached catch (e) {
        expect(e.reason, 'plan-limit');
        expect(e.tier, SubscriptionTier.plan1);
        expect(e.limit, 7);
        expect(e.currentLoad, 6.5);
        expect(e.projectedLoad, 7.5);
      }
    });

    test(
        'GOTCHA: Android-shaped Map<Object?, Object?> details parses '
        'without a TypeError (does NOT cast the outer map)', () async {
      final androidShapedDetails = <Object?, Object?>{
        'reason': 'subscription-inactive',
        'tier': 'plan2',
        // Android channel can also deliver ints as doubles or vice versa.
        'limit': 15.0,
        'currentLoad': 15,
        'projectedLoad': 16,
      };

      when(() => mockCallable.call<Map<String, dynamic>>(any())).thenThrow(
        FirebaseFunctionsException(
          code: 'resource-exhausted',
          message: 'Weighted-load limit reached.',
          details: androidShapedDetails,
        ),
      );

      try {
        await sut.accept('link-1');
        fail('expected LinkPromotionFailure\$PlanLimitReached');
      } on LinkPromotionFailure$PlanLimitReached catch (e) {
        expect(e.reason, 'subscription-inactive');
        expect(e.tier, SubscriptionTier.plan2);
        expect(e.limit, 15.0);
        expect(e.currentLoad, 15);
        expect(e.projectedLoad, 16);
      }
    });

    test(
        'malformed details (missing fields) degrades to '
        'LinkPromotionFailure\$PromotionUnavailable instead of throwing',
        () async {
      when(() => mockCallable.call<Map<String, dynamic>>(any())).thenThrow(
        FirebaseFunctionsException(
          code: 'resource-exhausted',
          message: 'Weighted-load limit reached.',
          details: const <String, dynamic>{'reason': 'plan-limit'},
        ),
      );

      await expectLater(
        () => sut.accept('link-1'),
        throwsA(isA<LinkPromotionFailure$PromotionUnavailable>()),
      );
    });

    test('null details degrades to LinkPromotionFailure\$PromotionUnavailable',
        () async {
      when(() => mockCallable.call<Map<String, dynamic>>(any())).thenThrow(
        FirebaseFunctionsException(
          code: 'resource-exhausted',
          message: 'Weighted-load limit reached.',
          details: null,
        ),
      );

      await expectLater(
        () => sut.accept('link-1'),
        throwsA(isA<LinkPromotionFailure$PromotionUnavailable>()),
      );
    });
  });

  group('TrainerLinkPromotionService.accept — failed-precondition', () {
    test('wrong-status maps to LinkPromotionFailure\$PromotionPrecondition',
        () async {
      when(() => mockCallable.call<Map<String, dynamic>>(any())).thenThrow(
        FirebaseFunctionsException(
          code: 'failed-precondition',
          message: 'wrong-status',
          details: null,
        ),
      );

      await expectLater(
        () => sut.accept('link-1'),
        throwsA(isA<LinkPromotionFailure$PromotionPrecondition>()),
      );
    });

    test('link-blocked maps to LinkPromotionFailure\$PromotionPrecondition',
        () async {
      when(() => mockCallable.call<Map<String, dynamic>>(any())).thenThrow(
        FirebaseFunctionsException(
          code: 'failed-precondition',
          message: 'link-blocked',
          details: null,
        ),
      );

      await expectLater(
        () => sut.accept('link-1'),
        throwsA(isA<LinkPromotionFailure$PromotionPrecondition>()),
      );
    });

    // Design D-5: not-found/permission-denied are non-retryable, same
    // "ya no disponible" branch as failed-precondition (matches the
    // coachHubDashboardAcceptPrecondition ARB description).
    for (final code in ['not-found', 'permission-denied']) {
      test('$code maps to LinkPromotionFailure\$PromotionPrecondition',
          () async {
        when(() => mockCallable.call<Map<String, dynamic>>(any())).thenThrow(
          FirebaseFunctionsException(
            code: code,
            message: 'boom',
            details: null,
          ),
        );

        await expectLater(
          () => sut.accept('link-1'),
          throwsA(isA<LinkPromotionFailure$PromotionPrecondition>()),
        );
      });
    }
  });

  group('TrainerLinkPromotionService.accept — other errors', () {
    for (final code in [
      'invalid-argument',
      'unauthenticated',
    ]) {
      test('$code maps to LinkPromotionFailure\$PromotionUnavailable',
          () async {
        when(() => mockCallable.call<Map<String, dynamic>>(any())).thenThrow(
          FirebaseFunctionsException(
            code: code,
            message: 'boom',
            details: null,
          ),
        );

        await expectLater(
          () => sut.accept('link-1'),
          throwsA(isA<LinkPromotionFailure$PromotionUnavailable>()),
        );
      });
    }

    test(
        'non-Firebase exception maps to LinkPromotionFailure\$PromotionUnavailable',
        () async {
      when(() => mockCallable.call<Map<String, dynamic>>(any()))
          .thenThrow(Exception('network error'));

      await expectLater(
        () => sut.accept('link-1'),
        throwsA(isA<LinkPromotionFailure$PromotionUnavailable>()),
      );
    });
  });
}
