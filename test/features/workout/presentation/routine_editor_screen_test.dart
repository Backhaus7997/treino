// Tests for RoutineEditorScreen — SCENARIO-457..463, SCENARIO-616..619
// REQ-COACH-PLANS-023..028 · REQ-USR-011

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/analytics/analytics_service.dart';
import 'package:treino/features/coach/presentation/coach_strings.dart';
import 'package:treino/features/workout/application/custom_exercise_providers.dart';
import 'package:treino/features/workout/application/exercise_providers.dart';
import 'package:treino/features/workout/application/routine_providers.dart'
    show routineRepositoryProvider;
import 'package:treino/features/workout/application/session_providers.dart'
    show currentUidProvider;
import 'package:treino/features/workout/application/user_routines_providers.dart'
    show userCreatedRoutinesProvider;
import 'package:treino/features/workout/data/routine_repository.dart';
import 'package:treino/features/workout/domain/custom_exercise.dart';
import 'package:treino/features/workout/domain/exercise.dart';
import 'package:treino/features/workout/domain/routine.dart';
import 'package:treino/features/profile/domain/experience_level.dart';
import 'package:treino/features/workout/domain/routine_source.dart';
import 'package:treino/features/workout/domain/routine_status.dart';
import 'package:treino/features/workout/domain/routine_visibility.dart';
import 'package:treino/features/workout/presentation/routine_editor_mode.dart';
import 'package:treino/features/workout/presentation/routine_editor_screen.dart';
import 'package:treino/features/workout/presentation/workout_strings.dart';

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

// ── Fixtures ─────────────────────────────────────────────────────────────────

Routine userCreatedRoutineFixture({
  String id = 'r1',
  String createdBy = 'athlete-1',
  RoutineStatus status = RoutineStatus.active,
}) =>
    Routine(
      id: id,
      name: 'Mi rutina',
      split: 'Full Body',
      level: ExperienceLevel.beginner,
      days: const [],
      source: RoutineSource.userCreated,
      visibility: RoutineVisibility.private,
      createdBy: createdBy,
      status: status,
    );

// ── Helper ────────────────────────────────────────────────────────────────────

Future<void> _pumpEditorWithMode(
  WidgetTester tester, {
  required RoutineEditorMode mode,
  required List<Override> overrides,
}) async {
  // RoutineEditorScreen is now a top-level route with its own Scaffold —
  // it lives OUTSIDE the ShellRoute so the bottom nav bar is not shown.
  final router = GoRouter(
    initialLocation: '/workout/editor',
    routes: [
      GoRoute(
        path: '/workout/editor',
        pageBuilder: (context, state) => NoTransitionPage(
          child: RoutineEditorScreen(mode: mode),
        ),
      ),
      GoRoute(
        path: '/coach',
        pageBuilder: (_, __) => const NoTransitionPage(
          child: Scaffold(body: Center(child: Text('CoachHome'))),
        ),
      ),
      GoRoute(
        path: '/workout',
        pageBuilder: (_, __) => const NoTransitionPage(
          child: Scaffold(body: Center(child: Text('WorkoutHome'))),
        ),
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

Future<void> _pumpEditor(
  WidgetTester tester, {
  required String athleteId,
  required List<Override> overrides,
}) =>
    _pumpEditorWithMode(
      tester,
      mode: TrainerAssigning(athleteId: athleteId),
      overrides: overrides,
    );

List<Override> _baseOverrides({
  RoutineRepository? repo,
}) {
  final mockRepo = repo ?? _MockRoutineRepository();
  return [
    currentUidProvider.overrideWithValue('trainer-1'),
    routineRepositoryProvider.overrideWithValue(mockRepo),
    exercisesProvider.overrideWith((ref) async => _kExercises),
    // The picker now ALSO watches the trainer's custom exercises (PR3 item 1).
    // Provide an empty stream so the tests don't try to hit live Firestore.
    customExercisesForTrainerStreamProvider('trainer-1').overrideWith(
      (ref) => Stream<List<CustomExercise>>.value(const <CustomExercise>[]),
    ),
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

    // TODO PR2-followup: rewrite for multi-select picker flow
    // (tap "Agregar ejercicio" → multi-select picker → tap exercise →
    // tap "Agregar 1 ejercicio" CTA → slot pre-filled). Picker behaviour
    // itself is covered by exercise_picker_sheet_test.dart (T-RER-024) and
    // exercise_picker_filter_combo_test.dart (T-RER-025).
    testWidgets(
        skip: true,
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

    // TODO PR2-followup: rewrite for multi-select picker flow.
    testWidgets(
        skip: true,
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

    // TODO PR2-followup: rewrite for multi-select picker flow.
    testWidgets(
        skip: true,
        'SCENARIO-460: successful submit shows SnackBar and pops back',
        (tester) async {
      final repo = _MockRoutineRepository();
      when(() => repo.createAssigned(any())).thenAnswer((inv) async {
        final r = inv.positionalArguments[0] as Routine;
        return r.copyWith(id: 'generated-id');
      });

      final router = GoRouter(
        initialLocation: '/workout/routine-editor/athlete-1',
        routes: [
          GoRoute(
            path: '/workout/routine-editor/:athleteId',
            pageBuilder: (context, state) => NoTransitionPage(
              child: RoutineEditorScreen(
                mode: TrainerAssigning(
                  athleteId: state.pathParameters['athleteId']!,
                ),
              ),
            ),
          ),
          GoRoute(
            path: '/coach/athlete/:athleteId',
            pageBuilder: (_, state) => NoTransitionPage(
              child: Scaffold(
                body: Text('Back:${state.pathParameters['athleteId']}'),
              ),
            ),
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
            customExercisesForTrainerStreamProvider('trainer-1').overrideWith(
              (ref) =>
                  Stream<List<CustomExercise>>.value(const <CustomExercise>[]),
            ),
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

    // TODO PR2-followup: rewrite for multi-select picker flow.
    testWidgets(
        skip: true,
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

  // ── SCENARIO-SS-001: "+ Superserie" gating ───────────────────────────────────

  group('RoutineEditorScreen — superset gating', () {
    testWidgets('SCENARIO-SS-001: TrainerAssigning shows "+ Superserie" button',
        (tester) async {
      await _pumpEditorWithMode(
        tester,
        mode: const TrainerAssigning(athleteId: 'athlete-1'),
        overrides: _baseOverrides(),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('add_superset_button')), findsOneWidget);
    });

    testWidgets(
        'SCENARIO-SS-002: TrainerTemplating shows "+ Superserie" button',
        (tester) async {
      await _pumpEditorWithMode(
        tester,
        mode: const TrainerTemplating(),
        overrides: _baseOverrides(),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('add_superset_button')), findsOneWidget);
    });

    testWidgets(
        'SCENARIO-SS-003: SelfCreating mode shows "+ Superserie" button '
        '(athletes build supersets with the same editor)', (tester) async {
      final overrides = [
        currentUidProvider.overrideWithValue('athlete-1'),
        routineRepositoryProvider.overrideWithValue(_MockRoutineRepository()),
        exercisesProvider.overrideWith((ref) async => _kExercises),
        customExercisesForTrainerStreamProvider('athlete-1').overrideWith(
          (ref) => Stream<List<CustomExercise>>.value(const <CustomExercise>[]),
        ),
        analyticsServiceProvider.overrideWithValue(FakeAnalyticsService()),
        userCreatedRoutinesProvider('athlete-1').overrideWith(
          (ref) => Stream.value(<Routine>[]),
        ),
      ];
      await _pumpEditorWithMode(
        tester,
        mode: const SelfCreating(),
        overrides: overrides,
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('add_superset_button')), findsOneWidget);
    });
  });

  // ── SCENARIO-616..619: RoutineEditorMode parametrization (T-USR-023) ─────────

  group('RoutineEditorScreen — mode parametrization', () {
    List<Override> selfCreatingOverrides({
      RoutineRepository? repo,
      String uid = 'athlete-1',
      List<Routine> userRoutines = const [],
    }) {
      final mockRepo = repo ?? _MockRoutineRepository();
      return [
        currentUidProvider.overrideWithValue(uid),
        routineRepositoryProvider.overrideWithValue(mockRepo),
        exercisesProvider.overrideWith((ref) async => _kExercises),
        customExercisesForTrainerStreamProvider(uid).overrideWith(
          (ref) => Stream<List<CustomExercise>>.value(const <CustomExercise>[]),
        ),
        analyticsServiceProvider.overrideWithValue(FakeAnalyticsService()),
        userCreatedRoutinesProvider(uid).overrideWith(
          (ref) => Stream.value(userRoutines),
        ),
      ];
    }

    // TODO PR2-followup: rewrite for multi-select picker flow.
    testWidgets(
        skip: true,
        'SCENARIO-616: TrainerAssigning mode calls createAssigned (regression)',
        (tester) async {
      final repo = _MockRoutineRepository();
      when(() => repo.createAssigned(any())).thenAnswer((inv) async {
        final r = inv.positionalArguments[0] as Routine;
        return r.copyWith(id: 'gen-id');
      });

      await _pumpEditorWithMode(
        tester,
        mode: const TrainerAssigning(athleteId: 'athlete-1'),
        overrides: _baseOverrides(repo: repo),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byKey(const Key('editor_name_field')), 'Plan Test');
      await tester.enterText(
          find.byKey(const Key('editor_split_field')), 'PPL');
      await tester.tap(find.text(CoachStrings.editorAddSlot));
      await tester.pumpAndSettle();
      await tester.tap(find.text(CoachStrings.exercisePicker));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sentadilla'));
      await tester.pumpAndSettle();

      await tester.tap(find.text(CoachStrings.editorSubmit));
      await tester.pumpAndSettle();

      verify(() => repo.createAssigned(any())).called(1);
      verifyNever(() => repo.createUserOwned(
            uid: any(named: 'uid'),
            draft: any(named: 'draft'),
          ));
    });

    // TODO PR2-followup: rewrite for multi-select picker flow.
    testWidgets(
        skip: true,
        'SCENARIO-617: SelfCreating mode calls createUserOwned with current uid',
        (tester) async {
      final repo = _MockRoutineRepository();
      when(() => repo.createUserOwned(
            uid: any(named: 'uid'),
            draft: any(named: 'draft'),
          )).thenAnswer((inv) async {
        final draft = inv.namedArguments[const Symbol('draft')] as Routine;
        return draft.copyWith(id: 'user-gen-id');
      });

      await _pumpEditorWithMode(
        tester,
        mode: const SelfCreating(),
        overrides: selfCreatingOverrides(repo: repo),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byKey(const Key('editor_name_field')), 'Mi Rutina');
      await tester.enterText(
          find.byKey(const Key('editor_split_field')), 'Full Body');
      await tester.tap(find.text(CoachStrings.editorAddSlot));
      await tester.pumpAndSettle();
      await tester.tap(find.text(CoachStrings.exercisePicker));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sentadilla'));
      await tester.pumpAndSettle();

      await tester.tap(find.text(WorkoutStrings.selfEditorSubmitLabel));
      await tester.pumpAndSettle();

      verify(() => repo.createUserOwned(
            uid: 'athlete-1',
            draft: any(named: 'draft'),
          )).called(1);
      verifyNever(() => repo.createAssigned(any()));
    });

    testWidgets(
        'SCENARIO-618: SelfCreating header shows selfEditorTitle; submit shows selfEditorSubmitLabel',
        (tester) async {
      await _pumpEditorWithMode(
        tester,
        mode: const SelfCreating(),
        overrides: selfCreatingOverrides(),
      );
      await tester.pumpAndSettle();

      expect(find.text(WorkoutStrings.selfEditorTitle), findsOneWidget);
      expect(find.text(WorkoutStrings.selfEditorSubmitLabel), findsOneWidget);
      // TrainerAssigning title must NOT appear
      expect(find.text(CoachStrings.editorTitle), findsNothing);
      // TrainerAssigning submit label must NOT appear
      expect(find.text(CoachStrings.editorSubmit), findsNothing);
    });

    testWidgets(
        'SCENARIO-616 (title regression): TrainerAssigning header shows editorTitle',
        (tester) async {
      await _pumpEditorWithMode(
        tester,
        mode: const TrainerAssigning(athleteId: 'athlete-1'),
        overrides: _baseOverrides(),
      );
      await tester.pumpAndSettle();

      expect(find.text(CoachStrings.editorTitle), findsOneWidget);
      expect(find.text(CoachStrings.editorSubmit), findsOneWidget);
      // SelfCreating strings must NOT appear
      expect(find.text(WorkoutStrings.selfEditorTitle), findsNothing);
    });

    // TODO PR2-followup: rewrite for multi-select picker flow.
    testWidgets(
        skip: true,
        'SCENARIO-619: SelfCreating with existingRoutineId surfaces stub toast',
        (tester) async {
      await _pumpEditorWithMode(
        tester,
        mode: const SelfCreating(existingRoutineId: 'existing-r1'),
        overrides: selfCreatingOverrides(),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byKey(const Key('editor_name_field')), 'Mi Rutina');
      await tester.enterText(
          find.byKey(const Key('editor_split_field')), 'Full Body');
      await tester.tap(find.text(CoachStrings.editorAddSlot));
      await tester.pumpAndSettle();
      await tester.tap(find.text(CoachStrings.exercisePicker));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sentadilla'));
      await tester.pumpAndSettle();

      await tester.tap(find.text(WorkoutStrings.selfEditorSubmitLabel));
      await tester.pumpAndSettle();

      expect(find.text(WorkoutStrings.editStubToast), findsOneWidget);
    });
  });
}
