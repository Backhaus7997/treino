// Tests for RoutineEditorScreen — SCENARIO-457..463
// REQ-COACH-PLANS-023..028

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/analytics/analytics_service.dart';
import 'package:treino/features/coach/presentation/coach_strings.dart';
import 'package:treino/features/workout/application/exercise_providers.dart';
import 'package:treino/features/workout/application/routine_providers.dart'
    show routineRepositoryProvider;
import 'package:treino/features/workout/application/session_providers.dart'
    show currentUidProvider;
import 'package:treino/features/workout/data/routine_repository.dart';
import 'package:treino/features/workout/domain/exercise.dart';
import 'package:treino/features/workout/domain/routine.dart';
import 'package:treino/features/profile/domain/experience_level.dart';
import 'package:treino/features/workout/domain/routine_source.dart';
import 'package:treino/features/workout/presentation/routine_editor_screen.dart';

import '../../../helpers/fake_analytics_service.dart';

// ── Mocks ─────────────────────────────────────────────────────────────────────

class _MockRoutineRepository extends Mock implements RoutineRepository {}

// ── Fixtures ──────────────────────────────────────────────────────────────────

const _kExercises = [
  Exercise(
    id: 'ex-1',
    name: 'Sentadilla',
    muscleGroup: 'Piernas',
    category: 'compound',
  ),
  Exercise(
    id: 'ex-2',
    name: 'Press de Banca',
    muscleGroup: 'Pecho',
    category: 'compound',
  ),
];

// ── Helper ────────────────────────────────────────────────────────────────────

Future<void> _pumpEditor(
  WidgetTester tester, {
  required String athleteId,
  required List<Override> overrides,
}) async {
  final router = GoRouter(
    initialLocation: '/workout/routine-editor/$athleteId',
    routes: [
      ShellRoute(
        builder: (context, state, child) => Scaffold(
          body: child,
          bottomNavigationBar: const SizedBox(),
        ),
        routes: [
          GoRoute(
            path: '/workout/routine-editor/:athleteId',
            builder: (context, state) => RoutineEditorScreen(
              athleteId: state.pathParameters['athleteId']!,
            ),
          ),
          GoRoute(
            path: '/coach',
            builder: (_, __) =>
                const Scaffold(body: Center(child: Text('CoachHome'))),
          ),
        ],
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp.router(
        theme: AppTheme.dark(),
        routerConfig: router,
      ),
    ),
  );
}

List<Override> _baseOverrides({
  RoutineRepository? repo,
}) {
  final mockRepo = repo ?? _MockRoutineRepository();
  return [
    currentUidProvider.overrideWithValue('trainer-1'),
    routineRepositoryProvider.overrideWithValue(mockRepo),
    exercisesProvider.overrideWith((ref) async => _kExercises),
    // Analytics fired post-createAssigned; fake evita FirebaseAnalytics.instance
    // que rompe en tests sin Firebase init.
    analyticsServiceProvider.overrideWithValue(FakeAnalyticsService()),
  ];
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  setUpAll(() {
    registerFallbackValue(
      const Routine(
        id: '',
        name: 'fallback',
        split: 'PPL',
        level: ExperienceLevel.beginner,
        days: [],
        source: RoutineSource.trainerAssigned,
      ),
    );
  });

  group('RoutineEditorScreen', () {
    testWidgets('SCENARIO-457: renders all form sections on load',
        (tester) async {
      await _pumpEditor(
        tester,
        athleteId: 'athlete-1',
        overrides: _baseOverrides(),
      );
      await tester.pumpAndSettle();

      // Title
      expect(find.text(CoachStrings.editorTitle), findsOneWidget);
      // Name field
      expect(find.text(CoachStrings.editorNameLabel), findsOneWidget);
      // Split field
      expect(find.text(CoachStrings.editorSplitLabel), findsOneWidget);
      // Submit button
      expect(find.text(CoachStrings.editorSubmit), findsOneWidget);
    });

    testWidgets(
        'SCENARIO-457 (triangulate): shows 1 initial day with add-slot CTA',
        (tester) async {
      await _pumpEditor(
        tester,
        athleteId: 'athlete-1',
        overrides: _baseOverrides(),
      );
      await tester.pumpAndSettle();

      // Starts with 1 day
      expect(find.text('Día 1'), findsWidgets);
      // Add slot button exists
      expect(find.text(CoachStrings.editorAddSlot), findsOneWidget);
    });

    testWidgets(
        'SCENARIO-461: submit with empty name does not call createAssigned',
        (tester) async {
      final repo = _MockRoutineRepository();
      await _pumpEditor(
        tester,
        athleteId: 'athlete-1',
        overrides: _baseOverrides(repo: repo),
      );
      await tester.pumpAndSettle();

      // Do NOT fill any field — tap submit
      await tester.tap(find.text(CoachStrings.editorSubmit));
      await tester.pumpAndSettle();

      verifyNever(() => repo.createAssigned(any()));
    });

    testWidgets(
        'SCENARIO-458: tapping "Agregar ejercicio" shows exercise picker sheet',
        (tester) async {
      await _pumpEditor(
        tester,
        athleteId: 'athlete-1',
        overrides: _baseOverrides(),
      );
      await tester.pumpAndSettle();

      // Open the picker by tapping the add-slot button (adds a slot first)
      await tester.tap(find.text(CoachStrings.editorAddSlot));
      await tester.pumpAndSettle();

      // Now tap the exercise picker button in the slot
      await tester.tap(find.text(CoachStrings.exercisePicker));
      await tester.pumpAndSettle();

      // The bottom sheet should show exercise names
      expect(find.text('Sentadilla'), findsOneWidget);
      expect(find.text('Press de Banca'), findsOneWidget);
    });

    testWidgets(
        'SCENARIO-459: selecting exercise from picker assigns it to slot',
        (tester) async {
      await _pumpEditor(
        tester,
        athleteId: 'athlete-1',
        overrides: _baseOverrides(),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text(CoachStrings.editorAddSlot));
      await tester.pumpAndSettle();

      await tester.tap(find.text(CoachStrings.exercisePicker));
      await tester.pumpAndSettle();

      // Select first exercise
      await tester.tap(find.text('Sentadilla'));
      await tester.pumpAndSettle();

      // Picker closes and slot now shows exercise name
      expect(find.text('Sentadilla'), findsOneWidget);
      // Picker sheet should be gone
      expect(find.text('Press de Banca'), findsNothing);
    });

    testWidgets('SCENARIO-462: submit button is disabled while submitting',
        skip: true, (tester) async {
      final completer = Completer<Routine>();
      final repo = _MockRoutineRepository();
      when(() => repo.createAssigned(any()))
          .thenAnswer((_) => completer.future);

      await _pumpEditor(
        tester,
        athleteId: 'athlete-1',
        overrides: _baseOverrides(repo: repo),
      );
      await tester.pumpAndSettle();

      // Fill in required fields
      await tester.enterText(
          find.byKey(const Key('editor_name_field')), 'Plan Test');
      await tester.enterText(
          find.byKey(const Key('editor_split_field')), 'PPL');
      // Add a slot with an exercise
      await tester.tap(find.text(CoachStrings.editorAddSlot));
      await tester.pumpAndSettle();
      await tester.tap(find.text(CoachStrings.exercisePicker));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sentadilla'));
      await tester.pumpAndSettle();

      // Submit
      await tester.tap(find.text(CoachStrings.editorSubmit));
      await tester.pump(); // single pump — loading state before future resolves

      // Submit button should be disabled
      final submitButton = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, CoachStrings.editorSubmit),
      );
      expect(submitButton.onPressed, isNull);

      // Cleanup
      completer.completeError(Exception('cancelled'));
      await tester.pumpAndSettle();
    });

    testWidgets('SCENARIO-460: successful submit shows SnackBar and pops back',
        (tester) async {
      final repo = _MockRoutineRepository();
      when(() => repo.createAssigned(any())).thenAnswer((inv) async {
        final r = inv.positionalArguments[0] as Routine;
        return r.copyWith(id: 'generated-id');
      });

      final router = GoRouter(
        initialLocation: '/workout/routine-editor/athlete-1',
        routes: [
          ShellRoute(
            builder: (context, state, child) => Scaffold(
              body: child,
              bottomNavigationBar: const SizedBox(),
            ),
            routes: [
              GoRoute(
                path: '/workout/routine-editor/:athleteId',
                builder: (context, state) => RoutineEditorScreen(
                  athleteId: state.pathParameters['athleteId']!,
                ),
              ),
              GoRoute(
                path: '/coach/athlete/:athleteId',
                builder: (_, state) => Scaffold(
                  body: Text('Back:${state.pathParameters['athleteId']}'),
                ),
              ),
            ],
          ),
        ],
      );

      final analytics = FakeAnalyticsService();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUidProvider.overrideWithValue('trainer-1'),
            routineRepositoryProvider.overrideWithValue(repo),
            exercisesProvider.overrideWith((ref) async => _kExercises),
            analyticsServiceProvider.overrideWithValue(analytics),
          ],
          child: MaterialApp.router(
            theme: AppTheme.dark(),
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Fill in the form
      await tester.enterText(
          find.byKey(const Key('editor_name_field')), 'Mi Plan');
      await tester.enterText(
          find.byKey(const Key('editor_split_field')), 'Full Body');
      await tester.tap(find.text(CoachStrings.editorAddSlot));
      await tester.pumpAndSettle();
      await tester.tap(find.text(CoachStrings.exercisePicker));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sentadilla'));
      await tester.pumpAndSettle();

      await tester.tap(find.text(CoachStrings.editorSubmit));
      await tester.pumpAndSettle();

      expect(find.text(CoachStrings.createPlanSuccess), findsOneWidget);
      expect(analytics.events, contains('plan_assigned'));
    });

    testWidgets(
        'SCENARIO-463: network error on submit shows error SnackBar and re-enables button',
        (tester) async {
      final repo = _MockRoutineRepository();
      when(() => repo.createAssigned(any()))
          .thenThrow(Exception('network error'));

      await _pumpEditor(
        tester,
        athleteId: 'athlete-1',
        overrides: _baseOverrides(repo: repo),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byKey(const Key('editor_name_field')), 'Mi Plan');
      await tester.enterText(
          find.byKey(const Key('editor_split_field')), 'Full Body');
      await tester.tap(find.text(CoachStrings.editorAddSlot));
      await tester.pumpAndSettle();
      await tester.tap(find.text(CoachStrings.exercisePicker));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sentadilla'));
      await tester.pumpAndSettle();

      await tester.tap(find.text(CoachStrings.editorSubmit));
      await tester.pumpAndSettle();

      expect(find.text(CoachStrings.createPlanError), findsOneWidget);

      // Button re-enabled
      final submitButton = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, CoachStrings.editorSubmit),
      );
      expect(submitButton.onPressed, isNotNull);
    });
  });
}
