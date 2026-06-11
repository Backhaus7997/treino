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
import 'package:treino/l10n/app_l10n.dart';
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
import 'package:treino/features/workout/domain/routine_day.dart';
import 'package:treino/features/workout/domain/routine_slot.dart';
import 'package:treino/features/workout/domain/set_enums.dart';
import 'package:treino/features/workout/domain/set_spec.dart';
import 'package:treino/features/profile/domain/experience_level.dart';
import 'package:treino/features/workout/domain/routine_source.dart';
import 'package:treino/features/workout/domain/routine_visibility.dart';
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
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        locale: const Locale('es', 'AR'),
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
    await tester.tap(find.text('Agregar ejercicio'));
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

  // ── Edit mode (existingRoutineId != null) ────────────────────────────────

  // Routine returned by getById for edit tests.
  const existingRoutine = Routine(
    id: 'routine-existing-1',
    name: 'Rutina Preexistente',
    split: null,
    level: ExperienceLevel.beginner,
    days: [],
    source: RoutineSource.userCreated,
    visibility: RoutineVisibility.private,
  );

  testWidgets(
      'SCENARIO-RER-EDIT-001: SelfCreating(existingRoutineId) hydrates name '
      'from getById into the name field', (tester) async {
    final repo = _MockRoutineRepository();
    when(() => repo.getById('routine-existing-1'))
        .thenAnswer((_) async => existingRoutine);

    await _pumpEditor(
      tester,
      mode: const SelfCreating(existingRoutineId: 'routine-existing-1'),
      overrides: _overrides(repo: repo),
    );

    // Verify getById was called with the correct id.
    verify(() => repo.getById('routine-existing-1')).called(1);

    // Name field must be populated with the existing routine's name.
    final nameField = tester.widget<TextField>(
      find.byKey(const Key('editor_name_field')),
    );
    expect(nameField.controller?.text, equals('Rutina Preexistente'));
  });

  testWidgets(
      'SCENARIO-RER-EDIT-002: SelfCreating(existingRoutineId) shows '
      '"Editar rutina" in the header instead of "Nueva rutina"',
      (tester) async {
    final repo = _MockRoutineRepository();
    when(() => repo.getById('routine-existing-1'))
        .thenAnswer((_) async => existingRoutine);

    await _pumpEditor(
      tester,
      mode: const SelfCreating(existingRoutineId: 'routine-existing-1'),
      overrides: _overrides(repo: repo),
    );

    expect(find.text(WorkoutStrings.selfEditorEditTitle), findsOneWidget);
    expect(find.text(WorkoutStrings.selfEditorTitle), findsNothing);
  });

  testWidgets(
      'SCENARIO-RER-EDIT-003: SelfCreating(existingRoutineId) submit calls '
      'updateUserOwned (not createUserOwned)', (tester) async {
    final repo = _MockRoutineRepository();
    when(() => repo.getById('routine-existing-1'))
        .thenAnswer((_) async => existingRoutine);
    when(() => repo.updateUserOwned(
          uid: any(named: 'uid'),
          draft: any(named: 'draft'),
        )).thenAnswer((inv) async {
      final draft = inv.namedArguments[const Symbol('draft')] as Routine;
      return draft;
    });

    await _pumpEditor(
      tester,
      mode: const SelfCreating(existingRoutineId: 'routine-existing-1'),
      overrides: _overrides(repo: repo),
    );

    // Name field is hydrated — still need to add a slot for valid form.
    // Tap + Agregar ejercicio to add a slot.
    await tester.tap(find.text('Agregar ejercicio'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Press de Banca').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text(WorkoutStrings.pickerAddButton(1)));
    await tester.pumpAndSettle();

    // Fill reps.
    final emptyFields = find.byType(TextField).evaluate().where((e) {
      final w = e.widget as TextField;
      return w.controller != null && w.controller!.text.isEmpty;
    }).toList();
    expect(emptyFields, isNotEmpty);
    final repsField = emptyFields.last.widget as TextField;
    await tester.enterText(find.byWidget(repsField), '8');
    await tester.pumpAndSettle();

    // Tap GUARDAR CAMBIOS.
    await tester.tap(find.widgetWithText(
        ElevatedButton, WorkoutStrings.selfEditorUpdateLabel));
    await tester.pumpAndSettle();

    // Must call updateUserOwned, not createUserOwned.
    verify(() => repo.updateUserOwned(
          uid: 'athlete-1',
          draft: any(named: 'draft'),
        )).called(1);
    verifyNever(() => repo.createUserOwned(
          uid: any(named: 'uid'),
          draft: any(named: 'draft'),
        ));
  });

  testWidgets(
      'SCENARIO-RER-EDIT-004: SelfCreating(existingRoutineId) with null '
      'getById shows not-found message', (tester) async {
    final repo = _MockRoutineRepository();
    when(() => repo.getById('gone-routine'))
        .thenAnswer((_) async => null); // deleted

    await _pumpEditor(
      tester,
      mode: const SelfCreating(existingRoutineId: 'gone-routine'),
      overrides: _overrides(repo: repo),
    );

    expect(find.text(WorkoutStrings.selfEditorNotFound), findsOneWidget);
    // Editor form must not be shown.
    expect(find.byKey(const Key('editor_name_field')), findsNothing);
  });

  // ── SCENARIO-RER-EDIT-005: round-trip data-loss test ─────────────────────
  //
  // Seeds a Routine with a rich day structure covering all SetSpec fields
  // (reps/range/duration, weightKg, set types, superset groups) and verifies
  // that hydrate→submit reproduces the EXACT same structure in the draft
  // passed to updateUserOwned — catching any silent field drops.

  testWidgets(
      'SCENARIO-RER-EDIT-005: hydrate→submit round-trip preserves full '
      'day/slot/set structure without data loss', (tester) async {
    // ── Seeded routine: 1 day, 3 slots ──────────────────────────────────────
    //
    // Slot A: reps-based, RepMode.single, 2 sets (warmup + working),
    //   weightKg on each set, varying reps (6 and 10).
    //   supersetGroupId = 7 — shares the group with slot C (non-consecutive).
    //
    // Slot B: duration-based, ExerciseMode.duration, 1 set with durationSeconds.
    //   standalone (supersetGroup: null) — sits between A and C so the two
    //   group-7 slots are NOT consecutive. This is intentional: the _blocks()
    //   renderer only groups CONSECUTIVE slots, so A and C are treated as
    //   standalone rows and no _SupersetGroupCard is rendered. The
    //   _buildDays() normalization counts ALL slots with the same group id
    //   (including non-consecutive ones), so group:7 SURVIVES in the captured
    //   draft as long as ≥2 slots share it — which is exactly what the
    //   round-trip must preserve.
    //
    // Slot C: reps-based, RepMode.range, 2 sets (normal + drop set),
    //   repsMin/repsMax. supersetGroupId = 7 — paired with slot A.
    //
    // This seed is rich enough that ANY dropped field changes the captured
    // draft: reps, repsMin, repsMax, weightKg, durationSeconds, set types
    // (warmup/normal/drop), ExerciseMode (reps/duration), RepMode
    // (single/range), and supersetGroup are all covered.

    const supersetGroupId = 7;

    const slotA = RoutineSlot(
      exerciseId: 'bench-press',
      exerciseName: 'Press de Banca',
      muscleGroup: 'chest',
      targetSets: 2,
      // targetRepsMin == targetRepsMax so RoutineSlot.effectiveRepMode returns
      // RepMode.single (not range). If they differ, effectiveRepMode overrides
      // to range even though repMode is explicitly set to single.
      targetRepsMin: 10,
      targetRepsMax: 10,
      restSeconds: 90,
      supersetGroup: supersetGroupId,
      exerciseMode: ExerciseMode.reps,
      repMode: RepMode.single,
      sets: [
        SetSpec(type: SetType.warmup, weightKg: 40.0, reps: 6),
        SetSpec(type: SetType.normal, weightKg: 80.0, reps: 10),
      ],
    );

    // slotB sits between slotA and slotC so A+C are non-consecutive
    // (prevents _SupersetGroupCard rendering, which has a known layout bug).
    const slotB = RoutineSlot(
      exerciseId: 'plank',
      exerciseName: 'Plancha',
      muscleGroup: 'core',
      targetSets: 1,
      targetRepsMin: 0,
      targetRepsMax: 0,
      restSeconds: 45,
      supersetGroup: null,
      exerciseMode: ExerciseMode.duration,
      repMode: RepMode.single,
      sets: [
        SetSpec(type: SetType.normal, durationSeconds: 60),
      ],
    );

    const slotC = RoutineSlot(
      exerciseId: 'pull-up',
      exerciseName: 'Dominadas',
      muscleGroup: 'back',
      targetSets: 2,
      targetRepsMin: 8,
      targetRepsMax: 12,
      restSeconds: 60,
      supersetGroup: supersetGroupId,
      exerciseMode: ExerciseMode.reps,
      repMode: RepMode.range,
      sets: [
        SetSpec(type: SetType.normal, repsMin: 8, repsMax: 12),
        SetSpec(type: SetType.drop, repsMin: 6, repsMax: 10),
      ],
    );

    const seededRoutine = Routine(
      id: 'rich-routine-1',
      name: 'Rutina Compleja',
      split: null,
      level: ExperienceLevel.beginner,
      days: [
        RoutineDay(
          dayNumber: 1,
          name: 'Día 1',
          // Order: A, B (duration/standalone), C — A and C share group 7
          // but are non-consecutive so they render as standalone rows.
          slots: [slotA, slotB, slotC],
        ),
      ],
      source: RoutineSource.userCreated,
      visibility: RoutineVisibility.private,
    );

    final repo = _MockRoutineRepository();
    when(() => repo.getById('rich-routine-1'))
        .thenAnswer((_) async => seededRoutine);

    Routine? capturedDraft;
    when(() => repo.updateUserOwned(
          uid: any(named: 'uid'),
          draft: any(named: 'draft'),
        )).thenAnswer((inv) async {
      capturedDraft = inv.namedArguments[const Symbol('draft')] as Routine;
      return capturedDraft!;
    });

    await _pumpEditor(
      tester,
      mode: const SelfCreating(existingRoutineId: 'rich-routine-1'),
      overrides: _overrides(repo: repo),
    );
    // Extra pump to ensure all setState callbacks (including the final
    // _loading = false rebuild) have completed and been laid out.
    await tester.pump();

    // Hydration complete — form should show the seeded name.
    final nameField = tester.widget<TextField>(
      find.byKey(const Key('editor_name_field')),
    );
    expect(nameField.controller?.text, equals('Rutina Compleja'),
        reason: 'hydration must populate the name field');

    // Verify the submit button is enabled before tapping.
    // This gives a clear diagnostic if _isValid is returning false.
    final submitBtn = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, WorkoutStrings.selfEditorUpdateLabel),
    );
    expect(submitBtn.onPressed, isNotNull,
        reason: '_isValid must be true after hydrating name + 3 valid slots');

    // Submit — the form is already valid (has name + hydrated slots with
    // all required fields). If _isValid is somehow false here, the tap will
    // be a no-op and the verify() below will fail with a clear message.
    await tester.tap(find.widgetWithText(
        ElevatedButton, WorkoutStrings.selfEditorUpdateLabel));
    await tester.pumpAndSettle();

    // updateUserOwned must have been called exactly once.
    verify(() => repo.updateUserOwned(
          uid: 'athlete-1',
          draft: any(named: 'draft'),
        )).called(1);
    expect(capturedDraft, isNotNull,
        reason: 'updateUserOwned must be called with a captured draft');

    // ── Primary assertions: draft.days must faithfully reproduce seeded data ─

    final days = capturedDraft!.days;
    expect(days, hasLength(1), reason: 'round-trip must preserve day count');

    final slots = days[0].slots;
    expect(slots, hasLength(3), reason: 'round-trip must preserve slot count');

    // ── Slot 0 (A): bench-press — warmup + working, weightKg, RepMode.single ─
    final capA = slots[0];
    expect(capA.exerciseId, equals('bench-press'));
    expect(capA.exerciseMode, equals(ExerciseMode.reps));
    expect(capA.repMode, equals(RepMode.single));
    // supersetGroupId shared with slot C (non-consecutive). _buildDays counts
    // all slots with group 7 → 2 hits → group preserved in draft.
    expect(capA.supersetGroup, equals(supersetGroupId),
        reason: 'supersetGroup must survive (group count ≥2)');
    expect(capA.sets, hasLength(2), reason: 'slot A must have 2 sets');
    expect(capA.sets[0].type, equals(SetType.warmup),
        reason: 'warmup set type must survive round-trip');
    expect(capA.sets[0].weightKg, equals(40.0),
        reason: 'weightKg must survive round-trip on warmup set');
    expect(capA.sets[0].reps, equals(6),
        reason: 'reps must survive round-trip on warmup set');
    expect(capA.sets[1].type, equals(SetType.normal));
    expect(capA.sets[1].weightKg, equals(80.0),
        reason: 'weightKg must survive round-trip on working set');
    expect(capA.sets[1].reps, equals(10),
        reason: 'reps must survive round-trip on working set');

    // ── Slot 1 (B): plank — duration-based, standalone ───────────────────────
    final capB = slots[1];
    expect(capB.exerciseId, equals('plank'));
    expect(capB.exerciseMode, equals(ExerciseMode.duration));
    expect(capB.supersetGroup, isNull,
        reason: 'standalone slot must have null supersetGroup');
    expect(capB.sets, hasLength(1));
    expect(capB.sets[0].durationSeconds, equals(60),
        reason: 'durationSeconds must survive round-trip');

    // ── Slot 2 (C): pull-up — RepMode.range, drop set, superset ─────────────
    final capC = slots[2];
    expect(capC.exerciseId, equals('pull-up'));
    expect(capC.exerciseMode, equals(ExerciseMode.reps));
    expect(capC.repMode, equals(RepMode.range));
    expect(capC.supersetGroup, equals(supersetGroupId),
        reason: 'supersetGroup must survive on slot C');
    expect(capC.sets, hasLength(2));
    expect(capC.sets[0].repsMin, equals(8),
        reason: 'repsMin must survive round-trip');
    expect(capC.sets[0].repsMax, equals(12),
        reason: 'repsMax must survive round-trip');
    expect(capC.sets[1].type, equals(SetType.drop),
        reason: 'drop set type must survive round-trip');
    expect(capC.sets[1].repsMin, equals(6));
    expect(capC.sets[1].repsMax, equals(10));
  });
}
