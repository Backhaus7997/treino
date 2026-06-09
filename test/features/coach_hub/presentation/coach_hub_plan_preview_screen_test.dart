import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart';
import 'package:treino/features/coach_hub/application/cf_providers.dart';
import 'package:treino/features/coach_hub/application/plan_import_providers.dart';
import 'package:treino/features/coach_hub/domain/parsed_plan.dart';
import 'package:treino/features/coach_hub/presentation/coach_hub_plan_preview_screen.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/domain/experience_level.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';
import 'package:treino/features/workout/application/exercise_providers.dart';
import 'package:treino/features/workout/domain/exercise.dart';

// ─── Mocks ──────────────────────────────────────────────────────────────────

class MockFirebaseFunctions extends Mock implements FirebaseFunctions {}

class MockHttpsCallable extends Mock implements HttpsCallable {}

class MockHttpsCallableResult extends Mock
    implements HttpsCallableResult<dynamic> {}

// ─── Helpers ─────────────────────────────────────────────────────────────────

UserProfile _trainerProfile() => UserProfile(
      uid: 'trainer-1',
      email: 'trainer@test.com',
      role: UserRole.trainer,
      displayName: 'Trainer Test',
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

/// A minimal ParsedPlan with one unmatched item for day 1.
ParsedPlan _planWithUnmatched() => const ParsedPlan(
      name: 'Test Plan',
      daysPerWeek: 1,
      durationWeeks: 4,
      level: ExperienceLevel.intermediate,
      days: [
        ParsedPlanDay(
          dayNumber: 1,
          items: [
            ParsedPlanItem(
              rowName: 'Sentadilla',
              exerciseId: null,
              exerciseName: 'Sentadilla',
              muscleGroup: null,
              sets: 3,
              repsMin: 10,
              repsMax: 12,
            ),
          ],
        ),
      ],
      unmatched: [
        ParsedPlanUnmatched(dayNumber: 1, rowName: 'Sentadilla'),
      ],
    );

Exercise _exercise({String id = 'ex-1', String name = 'Sentadilla'}) =>
    Exercise(
      id: id,
      name: name,
      muscleGroup: 'Legs',
      category: 'compound',
      aliases: const [],
    );

Widget _wrap(
  Widget child, {
  List<Override> overrides = const [],
}) =>
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(body: child),
      ),
    );

// ─── Tests ───────────────────────────────────────────────────────────────────

void main() {
  setUpAll(() {
    registerFallbackValue(<String, dynamic>{});
  });

  // ── T-CXP-029 RED ─────────────────────────────────────────────────────────

  group('SCENARIO-744: cloudFunctionsProvider is overridable in tests', () {
    test('cloudFunctionsProvider can be overridden with a mock', () {
      final mockFunctions = MockFirebaseFunctions();
      final container = ProviderContainer(
        overrides: [
          cloudFunctionsProvider.overrideWithValue(mockFunctions),
        ],
      );
      addTearDown(container.dispose);

      final functions = container.read(cloudFunctionsProvider);
      expect(functions, same(mockFunctions));
    });
  });

  // ── T-CXP-031 RED ────────────────────────────────────────────────────────

  group(
      'SCENARIO-745: _pickExerciseFor triggers addAlias callable with correct args',
      () {
    testWidgets(
        'after manual mapping, httpsCallable addAlias called with exerciseId and alias',
        (tester) async {
      final mockFunctions = MockFirebaseFunctions();
      final mockCallable = MockHttpsCallable();
      final mockResult = MockHttpsCallableResult();

      when(() => mockFunctions.httpsCallable('addAlias'))
          .thenReturn(mockCallable);
      when(() => mockCallable.call(any<Map<String, dynamic>>()))
          .thenAnswer((_) async => mockResult);

      final plan = _planWithUnmatched();
      final exercise = _exercise();

      await tester.pumpWidget(
        _wrap(
          const CoachHubPlanPreviewScreen(),
          overrides: [
            cloudFunctionsProvider.overrideWithValue(mockFunctions),
            parsedPlanProvider.overrideWith((ref) => plan),
            userProfileProvider.overrideWith(
              (ref) => Stream.value(_trainerProfile()),
            ),
            exercisesProvider.overrideWith(
              (ref) => Future.value([exercise]),
            ),
            linksForTrainerProvider('trainer-1').overrideWith(
              (ref) async => [],
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Tap "Asignar manualmente" to trigger manual mapping
      await tester.tap(find.text('Asignar manualmente'));
      await tester.pumpAndSettle();

      // Pick the exercise from the bottom sheet
      await tester.tap(find.text('Sentadilla').last);
      await tester.pumpAndSettle();

      // Verify addAlias was called with correct args
      verify(
        () => mockCallable.call(<String, dynamic>{
          'exerciseId': 'ex-1',
          'alias': 'Sentadilla',
        }),
      ).called(1);

      // Verify local state preserved (item is no longer unmatched)
      expect(find.text('sin match'), findsNothing);
    });
  });

  group('SCENARIO-746: _pickExerciseFor does not block on hanging CF', () {
    testWidgets(
        'UI returns to idle immediately even when CF never completes',
        (tester) async {
      final mockFunctions = MockFirebaseFunctions();
      final mockCallable = MockHttpsCallable();

      when(() => mockFunctions.httpsCallable('addAlias'))
          .thenReturn(mockCallable);
      // Never-completing future — simulates CF hang
      when(() => mockCallable.call(any<Map<String, dynamic>>()))
          .thenAnswer((_) => Completer<HttpsCallableResult<dynamic>>().future);

      final plan = _planWithUnmatched();
      final exercise = _exercise();

      await tester.pumpWidget(
        _wrap(
          const CoachHubPlanPreviewScreen(),
          overrides: [
            cloudFunctionsProvider.overrideWithValue(mockFunctions),
            parsedPlanProvider.overrideWith((ref) => plan),
            userProfileProvider.overrideWith(
              (ref) => Stream.value(_trainerProfile()),
            ),
            exercisesProvider.overrideWith(
              (ref) => Future.value([exercise]),
            ),
            linksForTrainerProvider('trainer-1').overrideWith(
              (ref) async => [],
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Asignar manualmente'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sentadilla').last);
      await tester.pumpAndSettle();

      // UI must be idle — no blocking spinner from _pickExerciseFor itself
      // The assign button is still enabled (not saving)
      expect(find.text('ASIGNAR PLAN'), findsOneWidget);
    });
  });

  // ── T-CXP-032 RED ────────────────────────────────────────────────────────

  group('SCENARIO-747: _addAlias swallows CF exceptions silently', () {
    testWidgets(
        'CF throws FirebaseFunctionsException — no error shown, mapping state preserved',
        (tester) async {
      final mockFunctions = MockFirebaseFunctions();
      final mockCallable = MockHttpsCallable();

      when(() => mockFunctions.httpsCallable('addAlias'))
          .thenReturn(mockCallable);
      when(() => mockCallable.call(any<Map<String, dynamic>>())).thenThrow(
        FirebaseFunctionsException(
          message: 'permission-denied',
          code: 'permission-denied',
        ),
      );

      final plan = _planWithUnmatched();
      final exercise = _exercise();

      await tester.pumpWidget(
        _wrap(
          const CoachHubPlanPreviewScreen(),
          overrides: [
            cloudFunctionsProvider.overrideWithValue(mockFunctions),
            parsedPlanProvider.overrideWith((ref) => plan),
            userProfileProvider.overrideWith(
              (ref) => Stream.value(_trainerProfile()),
            ),
            exercisesProvider.overrideWith(
              (ref) => Future.value([exercise]),
            ),
            linksForTrainerProvider('trainer-1').overrideWith(
              (ref) async => [],
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Asignar manualmente'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sentadilla').last);
      await tester.pumpAndSettle();

      // No error text shown to user
      expect(find.text('permission-denied'), findsNothing);
      // No exception propagated — widget tree still intact
      expect(find.byType(CoachHubPlanPreviewScreen), findsOneWidget);
      // Local mapping state preserved (unmatched badge gone)
      expect(find.text('sin match'), findsNothing);
    });
  });
}
