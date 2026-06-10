// Tests for RoutineEditorScreen — periodization week state machine (Phase 2).
//
// Covers:
//   SCENARIO-PERIOD-010/011: add week up to the 16-week cap; "+ Semana"
//                            disabled at the cap. (task 2.9)
//   SCENARIO-PERIOD-012/013: remove last week; "Quitar última" disabled at
//                            numWeeks == 1. (task 2.10)
//   SCENARIO-PERIOD-014:     tab switch shows that week's set data and
//                            switching back shows the original. (task 2.11)
//   SCENARIO-PERIOD-015/016: "Duplicar semana" copies the previous week with
//                            deep-copy independence. (task 2.12)
//   SCENARIO-PERIOD-017:     editing week N never mutates week N-1.
//                            (task 2.13)
//   SCENARIO-PERIOD-018:     save + reload round-trip preserves all weeks of
//                            a 4-week plan. (task 2.14)
//   SCENARIO-PERIOD-019:     a legacy single-week routine hydrates into Sem 1
//                            with no data loss. (task 2.15)
//   SCENARIO-PERIOD-020:     invalid set config on week 3 while viewing week
//                            1 blocks save and attributes the failing week.
//                            (task 2.16)
//   REQ-PERIOD-017 / SCENARIO-PERIOD-021: buildRoutineSlot derives weeklySets
//                            across N weeks and keeps legacy `sets` populated
//                            from week 0. (task 2.17)

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/analytics/analytics_service.dart';
import 'package:treino/features/coach/presentation/coach_strings.dart';
import 'package:treino/features/profile/domain/experience_level.dart';
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
import 'package:treino/features/workout/domain/routine_source.dart';
import 'package:treino/features/workout/domain/routine_visibility.dart';
import 'package:treino/features/workout/domain/set_enums.dart';
import 'package:treino/features/workout/domain/set_spec.dart';
import 'package:treino/features/workout/presentation/routine_editor_mode.dart';
import 'package:treino/features/workout/presentation/routine_editor_screen.dart';
import 'package:treino/features/workout/presentation/workout_strings.dart';

import '../../../fixtures/exercises.dart';
import '../../../helpers/fake_analytics_service.dart';

// ── Mocks ─────────────────────────────────────────────────────────────────────

class _MockRoutineRepository extends Mock implements RoutineRepository {}

// ── Helpers ───────────────────────────────────────────────────────────────────

Future<void> _pumpEditor(
  WidgetTester tester, {
  required RoutineEditorMode mode,
  required List<Override> overrides,
}) async {
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
  await tester.pumpAndSettle();
}

List<Override> _overrides({
  RoutineRepository? repo,
  String uid = 'user-1',
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
      (ref) => Stream.value(const []),
    ),
  ];
}

/// Adds "Press de Banca" to the first day via the exercise picker.
Future<void> _addBenchPress(WidgetTester tester) async {
  await tester.ensureVisible(find.text(CoachStrings.editorAddSlot));
  await tester.tap(find.text(CoachStrings.editorAddSlot));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Press de Banca').first);
  await tester.pumpAndSettle();
  await tester.tap(find.text(WorkoutStrings.pickerAddButton(1)));
  await tester.pumpAndSettle();
}

/// Fills the visible (selected week's) empty REPS field with [reps].
/// The KG field precedes REPS in traversal order, so the LAST empty
/// controller-backed field is the reps input — same pattern as the existing
/// editor tests.
Future<void> _fillVisibleReps(WidgetTester tester, String reps) async {
  final emptyFields = find.byType(TextField).evaluate().where((e) {
    final w = e.widget as TextField;
    return w.controller != null && w.controller!.text.isEmpty;
  }).toList();
  expect(emptyFields, isNotEmpty,
      reason: 'expected an empty reps field on the visible week');
  final repsField = emptyFields.last.widget as TextField;
  await tester.ensureVisible(find.byWidget(repsField));
  await tester.enterText(find.byWidget(repsField), reps);
  await tester.pumpAndSettle();
}

/// Replaces the content of the visible TextField currently holding [from].
Future<void> _replaceFieldText(
  WidgetTester tester,
  String from,
  String to,
) async {
  final field = tester
      .widgetList<TextField>(find.byType(TextField))
      .firstWhere((f) => f.controller?.text == from);
  await tester.ensureVisible(find.byWidget(field));
  await tester.enterText(find.byWidget(field), to);
  await tester.pumpAndSettle();
}

Future<void> _tapByKey(WidgetTester tester, String key) async {
  final finder = find.byKey(Key(key));
  if (finder.evaluate().isEmpty) {
    // The editor ListView inflates children lazily — after ensureVisible
    // scrolled down to a set row, the SEMANAS section gets unmounted. Drag
    // back to the top so the week controls exist again.
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 1000));
    await tester.pumpAndSettle();
  }
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

bool _textButtonEnabled(WidgetTester tester, String key) =>
    tester.widget<TextButton>(find.byKey(Key(key))).onPressed != null;

// ── Record helper for the weekly bridge ───────────────────────────────────────

({
  SetType type,
  double? weightKg,
  int? reps,
  int? repsMin,
  int? repsMax,
  int? durationSeconds,
}) _rep(int reps) => (
      type: SetType.normal,
      weightKg: null,
      reps: reps,
      repsMin: null,
      repsMax: null,
      durationSeconds: null,
    );

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

  // ── Task 2.9 — add week + cap ─────────────────────────────────────────────

  testWidgets(
      'SCENARIO-PERIOD-010/011: adds weeks up to 16 and disables "+ Semana" '
      'at the cap', (tester) async {
    await _pumpEditor(
      tester,
      mode: const SelfCreating(),
      overrides: _overrides(),
    );

    expect(find.byKey(const Key('week_tab_0')), findsOneWidget);
    expect(find.byKey(const Key('week_tab_1')), findsNothing);
    expect(_textButtonEnabled(tester, 'add_week_button'), isTrue);

    for (var i = 0; i < 15; i++) {
      await _tapByKey(tester, 'add_week_button');
    }

    expect(find.byKey(const Key('week_tab_15')), findsOneWidget);
    expect(find.byKey(const Key('week_tab_16')), findsNothing);
    expect(_textButtonEnabled(tester, 'add_week_button'), isFalse,
        reason: '"+ Semana" must be disabled at the 16-week cap');
  });

  // ── Task 2.10 — remove last week + floor ──────────────────────────────────

  testWidgets(
      'SCENARIO-PERIOD-012/013: removes the last week and disables '
      '"Quitar última" at one week', (tester) async {
    await _pumpEditor(
      tester,
      mode: const SelfCreating(),
      overrides: _overrides(),
    );

    expect(_textButtonEnabled(tester, 'remove_week_button'), isFalse,
        reason: '"Quitar última" must be disabled at numWeeks == 1');

    await _tapByKey(tester, 'add_week_button');
    await _tapByKey(tester, 'add_week_button');
    expect(find.byKey(const Key('week_tab_2')), findsOneWidget);

    await _tapByKey(tester, 'remove_week_button');
    expect(find.byKey(const Key('week_tab_2')), findsNothing);
    expect(find.byKey(const Key('week_tab_1')), findsOneWidget);

    await _tapByKey(tester, 'remove_week_button');
    expect(find.byKey(const Key('week_tab_1')), findsNothing);
    expect(_textButtonEnabled(tester, 'remove_week_button'), isFalse);
  });

  // ── Task 2.11 — tab switch shows per-week data ────────────────────────────

  testWidgets(
      'SCENARIO-PERIOD-014: switching tabs shows that week\'s sets and '
      'switching back shows the original data unchanged', (tester) async {
    await _pumpEditor(
      tester,
      mode: const SelfCreating(),
      overrides: _overrides(),
    );

    await _addBenchPress(tester);
    await _fillVisibleReps(tester, '8');

    // Add week — jumps to the new empty week: week 0 data must not leak in.
    await _tapByKey(tester, 'add_week_button');
    expect(find.text('8'), findsNothing,
        reason: 'a freshly added week starts empty (ADR-PB-04)');

    await _fillVisibleReps(tester, '12');

    await _tapByKey(tester, 'week_tab_0');
    expect(find.text('8'), findsOneWidget);
    expect(find.text('12'), findsNothing);

    await _tapByKey(tester, 'week_tab_1');
    expect(find.text('12'), findsOneWidget);
    expect(find.text('8'), findsNothing);
  });

  // ── Task 2.12 — duplicar semana ───────────────────────────────────────────

  testWidgets(
      'SCENARIO-PERIOD-015/016: "Duplicar semana" copies the previous week '
      'and the copy is deep — editing it never mutates the source',
      (tester) async {
    await _pumpEditor(
      tester,
      mode: const SelfCreating(),
      overrides: _overrides(),
    );

    // Disabled on week 0 — there is no previous week to copy.
    expect(_textButtonEnabled(tester, 'duplicate_week_button'), isFalse);

    await _addBenchPress(tester);
    await _fillVisibleReps(tester, '8');

    await _tapByKey(tester, 'add_week_button');
    expect(find.text('8'), findsNothing);

    await _tapByKey(tester, 'duplicate_week_button');
    expect(find.text('8'), findsOneWidget,
        reason: 'duplicating week 2 must copy week 1\'s prescription');

    // Deep-copy independence: editing the copy leaves the source intact.
    await _replaceFieldText(tester, '8', '10');
    await _tapByKey(tester, 'week_tab_0');
    expect(find.text('8'), findsOneWidget);
    expect(find.text('10'), findsNothing);
  });

  // ── Task 2.13 — week isolation while editing ──────────────────────────────

  testWidgets('SCENARIO-PERIOD-017: editing week N does not affect week N-1',
      (tester) async {
    await _pumpEditor(
      tester,
      mode: const SelfCreating(),
      overrides: _overrides(),
    );

    await _addBenchPress(tester);
    await _fillVisibleReps(tester, '8');

    await _tapByKey(tester, 'add_week_button');
    await _fillVisibleReps(tester, '12');
    await _replaceFieldText(tester, '12', '15');

    await _tapByKey(tester, 'week_tab_0');
    expect(find.text('8'), findsOneWidget);

    await _tapByKey(tester, 'week_tab_1');
    expect(find.text('15'), findsOneWidget);
  });

  // ── Task 2.14 — save + reload round-trip (4 weeks) ────────────────────────

  testWidgets(
      'SCENARIO-PERIOD-018: saving a 4-week plan submits numWeeks + full '
      'weeklySets and reloading preserves every week\'s prescription',
      (tester) async {
    final repo = _MockRoutineRepository();
    Routine? captured;
    when(() => repo.createAssigned(any())).thenAnswer((inv) async {
      captured = inv.positionalArguments.first as Routine;
      return captured!.copyWith(id: 'plan-4w');
    });

    await _pumpEditor(
      tester,
      mode: const TrainerAssigning(athleteId: 'athlete-x'),
      overrides: _overrides(repo: repo, uid: 'trainer-1'),
    );

    await tester.enterText(
        find.byKey(const Key('editor_name_field')), 'Plan 4 Semanas');
    await tester.enterText(find.byKey(const Key('editor_split_field')), 'PPL');
    await tester.pumpAndSettle();

    await _addBenchPress(tester);
    await _fillVisibleReps(tester, '8');
    await _tapByKey(tester, 'add_week_button');
    await _fillVisibleReps(tester, '10');
    await _tapByKey(tester, 'add_week_button');
    await _fillVisibleReps(tester, '12');
    await _tapByKey(tester, 'add_week_button');
    await _fillVisibleReps(tester, '15');

    await tester
        .tap(find.widgetWithText(ElevatedButton, CoachStrings.editorSubmit));
    await tester.pumpAndSettle();

    // Submitted draft carries the full periodization.
    expect(captured, isNotNull);
    expect(captured!.numWeeks, equals(4));
    final slot = captured!.days.first.slots.first;
    expect(slot.weeklySets, hasLength(4));
    expect(
      slot.weeklySets.map((wk) => wk.single.reps).toList(),
      equals([8, 10, 12, 15]),
    );
    // Legacy fields stay on week 0 (REQ-PERIOD-017 / ADR-PB-03).
    expect(slot.sets, equals(slot.weeklySets.first));
    expect(slot.targetReps, equals([8]));

    // Reload the saved plan — every week's prescription must hydrate back.
    final saved = captured!.copyWith(id: 'plan-4w');
    when(() => repo.getById('plan-4w')).thenAnswer((_) async => saved);

    await _pumpEditor(
      tester,
      mode: const TrainerAssigning(
        athleteId: 'athlete-x',
        existingPlanId: 'plan-4w',
      ),
      overrides: _overrides(repo: repo, uid: 'trainer-1'),
    );

    expect(find.byKey(const Key('week_tab_3')), findsOneWidget);
    expect(find.text('8'), findsOneWidget); // week 0 selected on load

    await _tapByKey(tester, 'week_tab_1');
    expect(find.text('10'), findsOneWidget);

    await _tapByKey(tester, 'week_tab_2');
    expect(find.text('12'), findsOneWidget);

    await _tapByKey(tester, 'week_tab_3');
    expect(find.text('15'), findsOneWidget);
  });

  // ── Task 2.15 — legacy single-week hydration ──────────────────────────────

  testWidgets(
      'SCENARIO-PERIOD-019: a legacy single-week routine hydrates into Sem 1 '
      'with no data loss', (tester) async {
    const legacy = Routine(
      id: 'legacy-1',
      name: 'Mi Rutina',
      split: null,
      level: ExperienceLevel.beginner,
      days: [
        RoutineDay(
          dayNumber: 1,
          name: 'Día 1',
          slots: [
            RoutineSlot(
              exerciseId: 'ex-bench',
              exerciseName: 'Press de Banca',
              muscleGroup: 'chest',
              targetSets: 2,
              targetRepsMin: 8,
              targetRepsMax: 8,
              restSeconds: 60,
              targetReps: [8, 8],
              sets: [SetSpec(reps: 8), SetSpec(reps: 8)],
              // weeklySets intentionally absent → legacy shape.
            ),
          ],
        ),
      ],
      source: RoutineSource.userCreated,
      visibility: RoutineVisibility.private,
    );

    final repo = _MockRoutineRepository();
    when(() => repo.getById('legacy-1')).thenAnswer((_) async => legacy);

    await _pumpEditor(
      tester,
      mode: const SelfCreating(existingRoutineId: 'legacy-1'),
      overrides: _overrides(repo: repo),
    );

    // Single week only, prescription intact.
    expect(find.byKey(const Key('week_tab_0')), findsOneWidget);
    expect(find.byKey(const Key('week_tab_1')), findsNothing);
    expect(find.text('8'), findsNWidgets(2),
        reason: 'both legacy sets must hydrate into week 1');
    expect(_textButtonEnabled(tester, 'remove_week_button'), isFalse);

    // Adding a week keeps week 1's original prescription untouched.
    await _tapByKey(tester, 'add_week_button');
    await _tapByKey(tester, 'week_tab_0');
    expect(find.text('8'), findsNWidgets(2));
  });

  // ── Task 2.16 — cross-week validation attribution ─────────────────────────

  testWidgets(
      'SCENARIO-PERIOD-020: an invalid week 3 blocks save while viewing week '
      '1 and the error is attributed to week 3', (tester) async {
    await _pumpEditor(
      tester,
      mode: const SelfCreating(),
      overrides: _overrides(),
    );

    await tester.enterText(
        find.byKey(const Key('editor_name_field')), 'Mi Plan');
    await tester.pumpAndSettle();

    await _addBenchPress(tester);
    await _fillVisibleReps(tester, '8');
    await _tapByKey(tester, 'add_week_button');
    await _fillVisibleReps(tester, '10');
    // Week 3 stays empty → invalid.
    await _tapByKey(tester, 'add_week_button');

    await _tapByKey(tester, 'week_tab_0');

    // Save blocked.
    final submit = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
    expect(submit.onPressed, isNull,
        reason: 'an invalid week anywhere must block save');

    // Attribution: badge on Sem 3's chip + hint naming week and day.
    expect(find.byKey(const Key('week_tab_warning_2')), findsOneWidget);
    expect(find.byKey(const Key('week_tab_warning_0')), findsNothing);
    expect(find.byKey(const Key('week_tab_warning_1')), findsNothing);
    expect(find.text('Sets incompletos en Sem 3 · Día 1'), findsOneWidget);

    // Fixing week 3 clears the attribution and unblocks save.
    await _tapByKey(tester, 'week_tab_2');
    await _fillVisibleReps(tester, '12');
    await _tapByKey(tester, 'week_tab_0');
    expect(find.byKey(const Key('week_tab_warning_2')), findsNothing);
    final submitAfter =
        tester.widget<ElevatedButton>(find.byType(ElevatedButton));
    expect(submitAfter.onPressed, isNotNull);
  });

  // ── Task 2.17 — buildRoutineSlot weekly derivation (unit) ─────────────────

  group('buildRoutineSlot weeklySets derivation (REQ-PERIOD-017)', () {
    test(
        'produces one SetSpec list per week and keeps legacy fields on '
        'week 0', () {
      final slot = RoutineEditorTestBridge.buildSlotBridgeWeekly(
        exerciseMode: ExerciseMode.reps,
        repMode: RepMode.single,
        weeklySets: [
          [_rep(8), _rep(8)],
          [_rep(10)],
          [_rep(12), _rep(12), _rep(12)],
        ],
      );

      expect(slot.weeklySets, hasLength(3));
      expect(slot.weeklySets[0].map((s) => s.reps), equals([8, 8]));
      expect(slot.weeklySets[1].map((s) => s.reps), equals([10]));
      expect(slot.weeklySets[2].map((s) => s.reps), equals([12, 12, 12]));

      // Legacy surface derives from WEEK 0 only (ADR-PB-03).
      expect(slot.sets, equals(slot.weeklySets[0]));
      expect(slot.targetSets, equals(2));
      expect(slot.targetReps, equals([8, 8]));
      expect(slot.targetRepsMin, equals(8));
      expect(slot.targetRepsMax, equals(8));
    });

    test('single-week slot writes exactly one weeklySets entry (ADR-PB-03)',
        () {
      final slot = RoutineEditorTestBridge.buildSlotBridgeWeekly(
        exerciseMode: ExerciseMode.reps,
        repMode: RepMode.single,
        weeklySets: [
          [_rep(8)],
        ],
      );

      expect(slot.weeklySets, hasLength(1));
      expect(slot.weeklySets.single.single.reps, equals(8));
      expect(slot.sets, equals(slot.weeklySets.single));
    });
  });
}
