// Tests for RoutineEditorScreen — athlete (SelfCreating) mode simplification.
// T-RER-032: SCENARIO-RER-020..023 + submit + validation.
// REQ-RER-012, REQ-RER-013, ADR-RER-04.

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
import 'package:treino/features/workout/domain/routine.dart';
import 'package:treino/features/profile/domain/experience_level.dart';
import 'package:treino/features/workout/domain/routine_source.dart';
import 'package:treino/features/workout/presentation/routine_editor_mode.dart';
import 'package:treino/features/workout/presentation/routine_editor_screen.dart';
import 'package:treino/features/workout/presentation/workout_strings.dart';

import '../../../helpers/fake_analytics_service.dart';
import '../../../fixtures/exercises.dart';

// ── Mocks ─────────────────────────────────────────────────────────────────────

class _MockRoutineRepository extends Mock implements RoutineRepository {}

// ── Helper — pump with explicit mode ─────────────────────────────────────────

Future<void> _pumpEditor(
  WidgetTester tester, {
  required RoutineEditorMode mode,
  required List<Override> overrides,
}) async {
  final router = GoRouter(
    initialLocation: '/workout/editor',
    routes: [
      ShellRoute(
        builder: (context, state, child) => Scaffold(body: child),
        routes: [
          GoRoute(
            path: '/workout/editor',
            builder: (context, state) => RoutineEditorScreen(mode: mode),
          ),
          GoRoute(
            path: '/coach',
            builder: (_, __) =>
                const Scaffold(body: Center(child: Text('CoachHome'))),
          ),
          GoRoute(
            path: '/workout',
            builder: (_, __) =>
                const Scaffold(body: Center(child: Text('WorkoutHome'))),
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
  await tester.pumpAndSettle();
}

// ── Shared overrides ──────────────────────────────────────────────────────────

List<Override> _overrides({
  RoutineRepository? repo,
  String uid = 'athlete-1',
  List<Routine> userRoutines = const [],
}) {
  final mockRepo = repo ?? _MockRoutineRepository();
  return [
    currentUidProvider.overrideWithValue(uid),
    routineRepositoryProvider.overrideWithValue(mockRepo),
    exercisesProvider.overrideWith((ref) async => kExerciseSeed),
    customExercisesForTrainerStreamProvider(uid).overrideWith(
      (ref) => Stream<List<CustomExercise>>.value(const <CustomExercise>[]),
    ),
    analyticsServiceProvider.overrideWithValue(FakeAnalyticsService()),
    userCreatedRoutinesProvider(uid).overrideWith(
      (ref) => Stream.value(userRoutines),
    ),
  ];
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  setUpAll(() {
    registerFallbackValue(
      const Routine(
        id: '',
        name: 'fallback',
        split: null,
        level: ExperienceLevel.beginner,
        days: [],
        source: RoutineSource.userCreated,
      ),
    );
  });

  // ── SCENARIO-RER-020: SelfCreating hides trainer-only fields ─────────────────

  testWidgets(
      'SCENARIO-RER-020: SelfCreating hides Split, Days/week and Level fields',
      (tester) async {
    await _pumpEditor(
      tester,
      mode: const SelfCreating(),
      overrides: _overrides(),
    );

    // Name field visible
    expect(find.byKey(const Key('editor_name_field')), findsOneWidget);

    // Split field hidden
    expect(find.byKey(const Key('editor_split_field')), findsNothing);

    // Days/week section label hidden
    expect(find.text('DÍAS/SEM'), findsNothing);

    // Level section label hidden
    expect(find.text('NIVEL'), findsNothing);

    // Days-of-plan section visible
    expect(find.text('DÍAS DEL PLAN'), findsOneWidget);
  });

  // ── SCENARIO-RER-021: SelfCreating shows name + days-of-plan ─────────────────

  testWidgets('SCENARIO-RER-021: SelfCreating shows name field and days editor',
      (tester) async {
    await _pumpEditor(
      tester,
      mode: const SelfCreating(),
      overrides: _overrides(),
    );

    expect(find.byKey(const Key('editor_name_field')), findsOneWidget);
    expect(find.text('DÍAS DEL PLAN'), findsOneWidget);
    // Starts with 1 day
    expect(find.text('Día 1'), findsWidgets);
  });

  // ── SCENARIO-RER-024: SelfCreating exposes supersets ─────────────────────────
  // The athlete builds routines with the SAME editor as trainers, including
  // superset blocks. The "+ Superserie" button is no longer trainer-gated.

  testWidgets('SCENARIO-RER-024: SelfCreating shows the add-superset button',
      (tester) async {
    await _pumpEditor(
      tester,
      mode: const SelfCreating(),
      overrides: _overrides(),
    );

    // Day tile starts expanded → the "+ Superserie" button is reachable.
    expect(find.byKey(const Key('add_superset_button')), findsOneWidget);
  });

  // ── SCENARIO-RER-022: TrainerAssigning shows all fields ───────────────────────

  testWidgets(
      'SCENARIO-RER-022: TrainerAssigning renders all trainer fields (regression)',
      (tester) async {
    await _pumpEditor(
      tester,
      mode: const TrainerAssigning(athleteId: 'athlete-1'),
      overrides: _overrides(uid: 'trainer-1'),
    );

    expect(find.byKey(const Key('editor_name_field')), findsOneWidget);
    expect(find.byKey(const Key('editor_split_field')), findsOneWidget);
    // DÍAS/SEM selector removed — it was a dead control (never persisted,
    // never created days). Day count is driven only by "DÍAS DEL PLAN".
    expect(find.text('DÍAS/SEM'), findsNothing);
    expect(find.text('NIVEL'), findsOneWidget);
    expect(find.text('DÍAS DEL PLAN'), findsOneWidget);
  });

  // ── SCENARIO-RER-023: TrainerTemplating shows all fields ──────────────────────

  testWidgets(
      'SCENARIO-RER-023: TrainerTemplating renders all trainer fields (regression)',
      (tester) async {
    await _pumpEditor(
      tester,
      mode: const TrainerTemplating(),
      overrides: _overrides(uid: 'trainer-1'),
    );

    expect(find.byKey(const Key('editor_name_field')), findsOneWidget);
    expect(find.byKey(const Key('editor_split_field')), findsOneWidget);
    // DÍAS/SEM selector removed — it was a dead control (never persisted,
    // never created days). Day count is driven only by "DÍAS DEL PLAN".
    expect(find.text('DÍAS/SEM'), findsNothing);
    expect(find.text('NIVEL'), findsOneWidget);
    expect(find.text('DÍAS DEL PLAN'), findsOneWidget);
  });

  // ── Validation: athlete mode passes without split ─────────────────────────────

  testWidgets(
      'SCENARIO-RER-020 (validation): SelfCreating submit enabled with name + '
      'day with slot; split not required', (tester) async {
    final repo = _MockRoutineRepository();
    when(() => repo.createUserOwned(
          uid: any(named: 'uid'),
          draft: any(named: 'draft'),
        )).thenAnswer((inv) async {
      final draft = inv.namedArguments[const Symbol('draft')] as Routine;
      return draft.copyWith(id: 'gen-id');
    });

    await _pumpEditor(
      tester,
      mode: const SelfCreating(),
      overrides: _overrides(repo: repo),
    );

    // Submit should be disabled (empty name)
    final submitDisabled = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, WorkoutStrings.selfEditorSubmitLabel),
    );
    expect(submitDisabled.onPressed, isNull,
        reason: 'submit disabled when name is empty');

    // Fill name — no split required for athlete
    await tester.enterText(
        find.byKey(const Key('editor_name_field')), 'Mi rutina');
    await tester.pumpAndSettle();

    // Submit still disabled — no slots yet
    final submitNoSlots = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, WorkoutStrings.selfEditorSubmitLabel),
    );
    expect(submitNoSlots.onPressed, isNull,
        reason: 'submit disabled when no slots');
  });

  // ── Submit path: athlete mode produces Routine(split: null, level: beginner) ─

  testWidgets(
      'SCENARIO: SelfCreating submit calls createUserOwned with split: null '
      'and level: beginner', (tester) async {
    final repo = _MockRoutineRepository();
    Routine? capturedDraft;
    when(() => repo.createUserOwned(
          uid: any(named: 'uid'),
          draft: any(named: 'draft'),
        )).thenAnswer((inv) async {
      capturedDraft = inv.namedArguments[const Symbol('draft')] as Routine;
      return capturedDraft!.copyWith(id: 'gen-id');
    });

    await _pumpEditor(
      tester,
      mode: const SelfCreating(),
      overrides: _overrides(repo: repo),
    );

    // Fill name
    await tester.enterText(
        find.byKey(const Key('editor_name_field')), 'Mi rutina');
    await tester.pumpAndSettle();

    // Add exercises via the add-slot button in Day 1
    await tester.tap(find.text(CoachStrings.editorAddSlot));
    await tester.pumpAndSettle();

    // Picker should have opened — tap on first exercise then the CTA
    expect(find.text('Press de Banca'), findsWidgets);
    await tester.tap(find.text('Press de Banca').first);
    await tester.pumpAndSettle();

    // Tap the sticky "Agregar 1 ejercicio" CTA
    expect(
      find.text(WorkoutStrings.pickerAddButton(1)),
      findsOneWidget,
    );
    await tester.tap(find.text(WorkoutStrings.pickerAddButton(1)));
    await tester.pumpAndSettle();

    // New per-set table validation: reps must be > 0.
    // The REPS column field has hint text 'reps' and starts empty.
    // We find it by locating empty TextFields (KG is also empty but appears
    // first; we need the second empty field which is the REPS field).
    // Strategy: collect all empty TextFields and fill the last one that isn't
    // the name field — in table-single-mode layout the order is: KG, REPS.
    // Filling the REPS field satisfies validation.
    final emptyFields = find.byType(TextField).evaluate().where((e) {
      final w = e.widget as TextField;
      return w.controller != null && w.controller!.text.isEmpty;
    }).toList();
    // emptyFields[0] = KG, emptyFields[1] = REPS (single mode, 1 set)
    // We need at least 1 empty field; fill the last one (REPS).
    expect(emptyFields, isNotEmpty, reason: 'expected empty REPS field');
    final repsField = emptyFields.last.widget as TextField;
    await tester.enterText(find.byWidget(repsField), '10');
    await tester.pumpAndSettle();

    // Now submit should be enabled
    final submitBtn = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, WorkoutStrings.selfEditorSubmitLabel),
    );
    expect(submitBtn.onPressed, isNotNull,
        reason: 'submit enabled after name + slot with reps filled');

    await tester.tap(find.widgetWithText(
        ElevatedButton, WorkoutStrings.selfEditorSubmitLabel));
    await tester.pumpAndSettle();

    verify(() => repo.createUserOwned(
          uid: 'athlete-1',
          draft: any(named: 'draft'),
        )).called(1);

    expect(capturedDraft, isNotNull);
    expect(capturedDraft!.split, isNull,
        reason: 'SelfCreating must submit split: null');
    expect(capturedDraft!.level, ExperienceLevel.beginner,
        reason: 'SelfCreating uses fixed beginner level');
  });
}
