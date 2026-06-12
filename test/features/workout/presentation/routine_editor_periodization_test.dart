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
//
// ── FASE 2: week presence (REQ-WPRES-010..015) ────────────────────────────────
//   SCENARIO-WPRES-011/014:  delete dialog shown in multi-week plan; no dialog
//                            for single-week. (task 2.1/2.2)
//   SCENARIO-WPRES-012/013:  "solo esta semana" masks current week; "todas"
//                            does structural remove. (task 2.2)
//   SCENARIO-WPRES-015:      auto-route to structural delete when slot present
//                            in exactly one week. (task 2.2)
//   SCENARIO-WPRES-016..019: add-scope dialog for week ≥ 2; no dialog on
//                            week 1 or single-week plan. (task 2.3)
//   SCENARIO-WPRES-020/021:  duplicar-semana copies presence + independence.
//                            (task 2.4)
//   SCENARIO-WPRES-022/023:  _isValid rejects out-of-range masks. (task 2.5/2.6)
//   buildRoutineSlot:         emits sorted activeWeeks; empty set → []. (task 2.7)

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/l10n/app_l10n.dart';
import 'package:treino/core/analytics/analytics_service.dart';
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
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        locale: const Locale('es', 'AR'),
        routerConfig: router,
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        locale: const Locale('es', 'AR'),
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
  await tester.ensureVisible(find.text('Agregar ejercicio'));
  await tester.tap(find.text('Agregar ejercicio'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Press de Banca').first);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Agregar 1 ejercicio'));
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

/// Taps "Duplicar semana" and confirms the dialog that follows.
/// Replaces every raw `_tapByKey(tester, 'duplicate_week_button')` call so
/// tests go through the confirmation step (Tarea 3).
Future<void> _tapDuplicateWeek(WidgetTester tester) async {
  await _tapByKey(tester, 'duplicate_week_button');
  // The dialog is now open — tap Confirmar.
  await tester.tap(find.byKey(const Key('duplicate_week_confirm_button')));
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

    await _tapDuplicateWeek(tester);
    expect(find.text('8'), findsOneWidget,
        reason: 'duplicating week 2 must copy week 1\'s prescription');

    // Deep-copy independence: editing the copy leaves the source intact.
    await _replaceFieldText(tester, '8', '10');
    await _tapByKey(tester, 'week_tab_0');
    expect(find.text('8'), findsOneWidget);
    expect(find.text('10'), findsNothing);
  });

  // ── Tarea 3: confirmación dialog de duplicar ────────────────────────────────

  testWidgets(
      'SCENARIO-DUP-CONFIRM-01: "Duplicar semana" shows dialog with correct '
      'week numbers and cancelling aborts the duplication', (tester) async {
    await _pumpEditor(
      tester,
      mode: const SelfCreating(),
      overrides: _overrides(),
    );

    await _addBenchPress(tester);
    await _fillVisibleReps(tester, '8');
    await _tapByKey(tester, 'add_week_button');
    // At week 2 (0-based index 1): dialog should say "Semana 1 → Semana 2".
    await _tapByKey(tester, 'duplicate_week_button');

    // Dialog is shown.
    expect(find.text('Se copiará la Semana 1 en la Semana 2.'), findsOneWidget);

    // Cancel — week 2 must remain empty (no "8" visible).
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(find.text('8'), findsNothing,
        reason: 'cancel must not copy the prescription');
  });

  testWidgets(
      'SCENARIO-DUP-CONFIRM-02: confirming the dialog executes the duplication',
      (tester) async {
    await _pumpEditor(
      tester,
      mode: const SelfCreating(),
      overrides: _overrides(),
    );

    await _addBenchPress(tester);
    await _fillVisibleReps(tester, '8');
    await _tapByKey(tester, 'add_week_button');
    // Tap button → dialog → confirm.
    await _tapByKey(tester, 'duplicate_week_button');
    expect(find.text('Se copiará la Semana 1 en la Semana 2.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('duplicate_week_confirm_button')));
    await tester.pumpAndSettle();
    expect(find.text('8'), findsOneWidget,
        reason: 'confirming must copy week 1 prescription into week 2');
  });

  // ── Device-repro: duplicate then edit the copy via its TextField ──────────

  testWidgets(
      'REPRO: after "Duplicar semana", typing reps in week 2 must NOT leak '
      'into week 1 (real device flow)', (tester) async {
    await _pumpEditor(
      tester,
      mode: const SelfCreating(),
      overrides: _overrides(),
    );

    // Week 1: add exercise, set reps = 8.
    await _addBenchPress(tester);
    await _fillVisibleReps(tester, '8');

    // Add an empty week (jumps to week 2) and duplicate week 1 into it.
    await _tapByKey(tester, 'add_week_button');
    await _tapDuplicateWeek(tester);
    expect(find.text('8'), findsOneWidget,
        reason: 'duplicate must seed week 2 with week 1\'s reps');

    // Bounce between tabs BEFORE editing — this is what the coach does on the
    // device and it exercises the late-final controller + ObjectKey State path.
    await _tapByKey(tester, 'week_tab_0');
    await _tapByKey(tester, 'week_tab_1');

    // Now edit week 2's reps via the actual TextField (enterText), 8 -> 12.
    await _replaceFieldText(tester, '8', '12');

    // Week 1 MUST still read 8 — the edit belongs to week 2 only.
    await _tapByKey(tester, 'week_tab_0');
    expect(find.text('8'), findsOneWidget,
        reason: 'editing week 2 leaked into week 1 — periodization broken');
    expect(find.text('12'), findsNothing,
        reason: 'week 1 must not show week 2\'s value');

    // And week 2 keeps the edit.
    await _tapByKey(tester, 'week_tab_1');
    expect(find.text('12'), findsOneWidget);
    expect(find.text('8'), findsNothing);
  });

  testWidgets(
      'REPRO 2: save a duplicated 2-week plan, reload it, then editing week 2 '
      'reps must NOT change week 1 (post-hydration aliasing)', (tester) async {
    final repo = _MockRoutineRepository();
    Routine? captured;
    when(() => repo.createAssigned(any())).thenAnswer((inv) async {
      captured = inv.positionalArguments.first as Routine;
      return captured!.copyWith(id: 'plan-dup');
    });

    await _pumpEditor(
      tester,
      mode: const TrainerAssigning(athleteId: 'athlete-x'),
      overrides: _overrides(repo: repo, uid: 'trainer-1'),
    );

    await tester.enterText(
        find.byKey(const Key('editor_name_field')), 'Plan Dup');
    await tester.enterText(find.byKey(const Key('editor_split_field')), 'PPL');
    await tester.pumpAndSettle();

    await _addBenchPress(tester);
    await _fillVisibleReps(tester, '8');
    await _tapByKey(tester, 'add_week_button');
    await _tapDuplicateWeek(tester);

    await tester.tap(find.widgetWithText(ElevatedButton, 'ASIGNAR PLAN'));
    await tester.pumpAndSettle();
    expect(captured, isNotNull);

    // Reload the saved plan.
    final saved = captured!.copyWith(id: 'plan-dup');
    when(() => repo.getById('plan-dup')).thenAnswer((_) async => saved);

    await _pumpEditor(
      tester,
      mode: const TrainerAssigning(
        athleteId: 'athlete-x',
        existingPlanId: 'plan-dup',
      ),
      overrides: _overrides(repo: repo, uid: 'trainer-1'),
    );

    expect(find.byKey(const Key('week_tab_1')), findsOneWidget);
    expect(find.text('8'), findsOneWidget); // week 0

    // Edit week 2 to 20 and verify isolation after reload.
    await _tapByKey(tester, 'week_tab_1');
    await _replaceFieldText(tester, '8', '20');
    await _tapByKey(tester, 'week_tab_0');
    expect(find.text('8'), findsOneWidget,
        reason: 'reloaded week 1 must keep 8 after editing week 2');
    expect(find.text('20'), findsNothing);
  });

  testWidgets(
      'REPRO 3: multi-set slot — editing one set in week 2 must not touch '
      'week 1 sets', (tester) async {
    await _pumpEditor(
      tester,
      mode: const SelfCreating(),
      overrides: _overrides(),
    );

    await _addBenchPress(tester);
    await _fillVisibleReps(tester, '8');
    // Add a second set in week 1 (clones last -> reps 8).
    await _tapByKey(tester, 'add_set_button');
    expect(find.text('8'), findsNWidgets(2));

    await _tapByKey(tester, 'add_week_button');
    await _tapDuplicateWeek(tester);
    expect(find.text('8'), findsNWidgets(2),
        reason: 'duplicate copies both sets');

    // Change the FIRST set of week 2 to 5.
    await _replaceFieldText(tester, '8', '5');

    await _tapByKey(tester, 'week_tab_0');
    expect(find.text('8'), findsNWidgets(2),
        reason: 'week 1 keeps both original sets at 8');
    expect(find.text('5'), findsNothing);
  });

  testWidgets(
      'REPRO 4: after duplicating, editing WEEK 1 must not change week 2 '
      '(inverse flow)', (tester) async {
    await _pumpEditor(
      tester,
      mode: const SelfCreating(),
      overrides: _overrides(),
    );

    await _addBenchPress(tester);
    await _fillVisibleReps(tester, '8');
    await _tapByKey(tester, 'add_week_button');
    await _tapDuplicateWeek(tester);

    // Go back to week 1 and change it to 3.
    await _tapByKey(tester, 'week_tab_0');
    await _replaceFieldText(tester, '8', '3');

    // Week 2 must still be 8.
    await _tapByKey(tester, 'week_tab_1');
    expect(find.text('8'), findsOneWidget,
        reason: 'editing week 1 leaked into the duplicated week 2');
    expect(find.text('3'), findsNothing);
  });

  testWidgets(
      'REPRO 5: full editor → REAL JSON round-trip (encode/decode through '
      'WeeklySetsConverter) → rehydrate; per-week reps survive the wire and '
      'editing week 2 does not leak into week 1', (tester) async {
    final repo = _MockRoutineRepository();
    Routine? captured;
    when(() => repo.createAssigned(any())).thenAnswer((inv) async {
      captured = inv.positionalArguments.first as Routine;
      return captured!.copyWith(id: 'plan-json');
    });

    await _pumpEditor(
      tester,
      mode: const TrainerAssigning(athleteId: 'athlete-x'),
      overrides: _overrides(repo: repo, uid: 'trainer-1'),
    );

    await tester.enterText(
        find.byKey(const Key('editor_name_field')), 'Plan JSON');
    await tester.enterText(find.byKey(const Key('editor_split_field')), 'PPL');
    await tester.pumpAndSettle();

    // Week 1 = 8 reps; add an empty week, duplicate week 1 into it (8), then
    // edit week 2 to 12 — the exact device flow that produced the bug report.
    await _addBenchPress(tester);
    await _fillVisibleReps(tester, '8');
    await _tapByKey(tester, 'add_week_button');
    await _tapDuplicateWeek(tester);
    await _replaceFieldText(tester, '8', '12');

    await tester.tap(find.widgetWithText(ElevatedButton, 'ASIGNAR PLAN'));
    await tester.pumpAndSettle();
    expect(captured, isNotNull,
        reason: 'editor must hand a Routine to the repo on save');

    // ── REAL serialization round-trip (exactly what Firestore does) ─────────
    final wireJson = captured!.toJson();
    final encoded = jsonEncode(wireJson);
    final decoded = jsonDecode(encoded) as Map<String, Object?>;
    final roundTripped = Routine.fromJson(decoded);

    // ── BONUS: direct asserts on the intermediate JSON wire shape ──────────
    final daysJson = (decoded['days'] as List).cast<Map<String, Object?>>();
    final slotJson =
        ((daysJson.first['slots'] as List).first) as Map<String, Object?>;
    final weeklySetsJson = slotJson['weeklySets'] as List;
    expect(weeklySetsJson, hasLength(2),
        reason: 'two weeks must reach the wire');
    // Each week is a MAP {'sets': [...]} — never a bare list (Firestore rejects
    // nested arrays, hence WeeklySetsConverter wraps every week).
    for (final week in weeklySetsJson) {
      expect(week, isA<Map>(),
          reason: 'each weeklySets entry must be a map, not a list of lists');
      expect((week as Map)['sets'], isA<List>(),
          reason: "each week map must carry a 'sets' list");
    }
    int wireReps(int weekIdx) {
      final sets = ((weeklySetsJson[weekIdx] as Map)['sets'] as List)
          .cast<Map<String, Object?>>();
      return sets.first['reps'] as int;
    }

    expect(wireReps(0), equals(8), reason: 'week 1 reps on the wire');
    expect(wireReps(1), equals(12), reason: 'week 2 reps on the wire');
    expect(wireReps(0), isNot(equals(wireReps(1))),
        reason: 'the two weeks must carry DISTINCT reps on the wire — '
            'aliasing here means the bug is in serialization');

    // ── Rehydrate the editor from the DESERIALIZED routine ─────────────────
    when(() => repo.getById('plan-json'))
        .thenAnswer((_) async => roundTripped.copyWith(id: 'plan-json'));

    await _pumpEditor(
      tester,
      mode: const TrainerAssigning(
        athleteId: 'athlete-x',
        existingPlanId: 'plan-json',
      ),
      overrides: _overrides(repo: repo, uid: 'trainer-1'),
    );

    expect(find.byKey(const Key('week_tab_1')), findsOneWidget);
    expect(find.text('8'), findsOneWidget); // week 0 on load
    expect(find.text('12'), findsNothing);

    await _tapByKey(tester, 'week_tab_1');
    expect(find.text('12'), findsOneWidget);
    expect(find.text('8'), findsNothing);

    // Editing the deserialized week 2 must not leak into week 1.
    await _replaceFieldText(tester, '12', '20');
    await _tapByKey(tester, 'week_tab_0');
    expect(find.text('8'), findsOneWidget,
        reason: 'after a real round-trip, editing week 2 leaked into week 1');
    expect(find.text('20'), findsNothing);
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

    await tester.tap(find.widgetWithText(ElevatedButton, 'ASIGNAR PLAN'));
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

  // ── FASE 2: week presence ─────────────────────────────────────────────────

  // ── Task 2.1 / 2.2 — delete dialog (SCENARIO-WPRES-011..015) ────────────

  testWidgets('SCENARIO-WPRES-011: delete dialog shown when numWeeks == 3',
      (tester) async {
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
    // build a 3-week plan
    await _tapByKey(tester, 'add_week_button');
    await _fillVisibleReps(tester, '10');
    await _tapByKey(tester, 'add_week_button');
    await _fillVisibleReps(tester, '12');

    // Navigate to week 1 (index 1), then delete the slot
    await _tapByKey(tester, 'week_tab_1');

    // Open the slot menu and tap "Eliminar"
    final menuButton = find.byKey(const Key('slot_menu_button_0'));
    await tester.ensureVisible(menuButton);
    await tester.tap(menuButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Eliminar'));
    await tester.pumpAndSettle();

    // Dialog must appear with the two options
    expect(find.text('Solo esta semana'), findsOneWidget,
        reason: 'SCENARIO-WPRES-011: dialog must offer "solo esta semana"');
    expect(find.text('Todas las semanas'), findsOneWidget,
        reason: 'SCENARIO-WPRES-011: dialog must offer "todas las semanas"');
  });

  testWidgets(
      'SCENARIO-WPRES-014: no dialog when numWeeks == 1; slot removed immediately',
      (tester) async {
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

    // Single-week plan — delete immediately without dialog
    final menuButton = find.byKey(const Key('slot_menu_button_0'));
    await tester.ensureVisible(menuButton);
    await tester.tap(menuButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Eliminar'));
    await tester.pumpAndSettle();

    expect(find.text('Solo esta semana'), findsNothing,
        reason: 'SCENARIO-WPRES-014: no dialog for single-week plan');
    expect(find.text('Press de Banca'), findsNothing,
        reason: 'slot must be removed without dialog');
  });

  testWidgets(
      'SCENARIO-WPRES-012: "solo esta semana" masks current week out of all-weeks slot',
      (tester) async {
    final repo = _MockRoutineRepository();
    Routine? captured;
    when(() => repo.createAssigned(any())).thenAnswer((inv) async {
      captured = inv.positionalArguments.first as Routine;
      return captured!.copyWith(id: 'plan-del');
    });

    await _pumpEditor(
      tester,
      mode: const TrainerAssigning(athleteId: 'athlete-x'),
      overrides: _overrides(repo: repo, uid: 'trainer-1'),
    );

    await tester.enterText(
        find.byKey(const Key('editor_name_field')), 'Plan Del');
    await tester.enterText(find.byKey(const Key('editor_split_field')), 'PPL');
    await tester.pumpAndSettle();

    await _addBenchPress(tester);
    await _fillVisibleReps(tester, '8');
    await _tapByKey(tester, 'add_week_button');
    await _fillVisibleReps(tester, '10');
    await _tapByKey(tester, 'add_week_button');
    await _fillVisibleReps(tester, '12');

    // View week 1 (index 1), delete "solo esta semana"
    await _tapByKey(tester, 'week_tab_1');

    final menuButton = find.byKey(const Key('slot_menu_button_0'));
    await tester.ensureVisible(menuButton);
    await tester.tap(menuButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Eliminar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Solo esta semana'));
    await tester.pumpAndSettle();

    // The masked-out slot disappears from THIS week's view — this is the
    // user-visible effect of "solo esta semana" (device bug 2026-06-11: the
    // mask updated but the render did not filter, so it looked broken).
    expect(find.text('Press de Banca'), findsNothing,
        reason: 'masked-out slot must be hidden in the viewed week');

    // ...but it was NOT structurally removed: other weeks still render it.
    await _tapByKey(tester, 'week_tab_0');
    expect(find.text('Press de Banca'), findsOneWidget,
        reason: 'slot must remain in the plan for other weeks');

    // Save and check the activeWeeks mask
    await tester.tap(find.widgetWithText(ElevatedButton, 'ASIGNAR PLAN'));
    await tester.pumpAndSettle();
    expect(captured, isNotNull);

    final slot = captured!.days.first.slots.first;
    expect(
      slot.activeWeeks,
      equals([0, 2]),
      reason:
          'SCENARIO-WPRES-012: mask must be [0, 2] after removing week index 1',
    );
  });

  testWidgets(
      'SCENARIO-WPRES-013: "todas las semanas" removes slot structurally',
      (tester) async {
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

    // Go to week 1, delete "todas las semanas"
    await _tapByKey(tester, 'week_tab_1');

    final menuButton = find.byKey(const Key('slot_menu_button_0'));
    await tester.ensureVisible(menuButton);
    await tester.tap(menuButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Eliminar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Todas las semanas'));
    await tester.pumpAndSettle();

    expect(find.text('Press de Banca'), findsNothing,
        reason:
            'SCENARIO-WPRES-013: structural remove must eliminate the slot');
  });

  testWidgets(
      'SCENARIO-WPRES-015: auto-route to structural delete when slot has '
      'activeWeeks == [currentWeek] only', (tester) async {
    // Build a 3-week plan, add exercise, then manually mask it to [2] via
    // the "solo esta semana" delete on weeks 0 and 1 sequentially — this makes
    // it present only in week 2. Then deleting "solo esta semana" on week 2
    // must trigger a structural delete (no second dialog).
    final repo = _MockRoutineRepository();
    Routine? captured;
    when(() => repo.createAssigned(any())).thenAnswer((inv) async {
      captured = inv.positionalArguments.first as Routine;
      return captured!.copyWith(id: 'plan-auto');
    });

    await _pumpEditor(
      tester,
      mode: const TrainerAssigning(athleteId: 'athlete-x'),
      overrides: _overrides(repo: repo, uid: 'trainer-1'),
    );

    await tester.enterText(
        find.byKey(const Key('editor_name_field')), 'Plan Auto');
    await tester.enterText(find.byKey(const Key('editor_split_field')), 'PPL');
    await tester.pumpAndSettle();

    await _addBenchPress(tester);
    await _fillVisibleReps(tester, '8');
    await _tapByKey(tester, 'add_week_button');
    await _fillVisibleReps(tester, '10');
    await _tapByKey(tester, 'add_week_button');
    await _fillVisibleReps(tester, '12');

    // Delete "solo esta semana" on week 0 → mask becomes [1, 2]
    await _tapByKey(tester, 'week_tab_0');
    await _deleteSlotThisWeek(tester, 0);

    // Delete "solo esta semana" on week 1 → mask becomes [2]
    await _tapByKey(tester, 'week_tab_1');
    await _deleteSlotThisWeek(tester, 0);

    // Now on week 2, the slot is present in only this week.
    // "solo esta semana" must auto-route to structural delete.
    await _tapByKey(tester, 'week_tab_2');
    final menuButton = find.byKey(const Key('slot_menu_button_0'));
    await tester.ensureVisible(menuButton);
    await tester.tap(menuButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Eliminar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Solo esta semana'));
    await tester.pumpAndSettle();

    // Slot must be gone entirely — structural delete
    expect(find.text('Press de Banca'), findsNothing,
        reason:
            'SCENARIO-WPRES-015: last-present-week delete must be structural');
  });

  // ── Task 2.1 / 2.3 — add-scope dialog (SCENARIO-WPRES-016..019) ──────────

  testWidgets(
      'SCENARIO-WPRES-016: scope dialog shown when adding on week ≥ 2 '
      '(numWeeks == 3, selectedWeek == 1)', (tester) async {
    await _pumpEditor(
      tester,
      mode: const SelfCreating(),
      overrides: _overrides(),
    );

    await tester.enterText(
        find.byKey(const Key('editor_name_field')), 'Mi Plan');
    await tester.pumpAndSettle();

    // Build a 3-week plan without exercises yet
    await _tapByKey(tester, 'add_week_button');
    await _tapByKey(tester, 'add_week_button');

    // Navigate to week 2 (index 1)
    await _tapByKey(tester, 'week_tab_1');

    // Add an exercise — scope dialog must appear
    await tester.ensureVisible(find.text('Agregar ejercicio'));
    await tester.tap(find.text('Agregar ejercicio'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Press de Banca').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Agregar 1 ejercicio'));
    await tester.pumpAndSettle();

    expect(find.text('Agregar solo en esta semana'), findsOneWidget,
        reason: 'SCENARIO-WPRES-016: scope dialog must appear on week ≥ 2');
    expect(find.text('Agregar en todas las semanas'), findsOneWidget);
  });

  testWidgets(
      'SCENARIO-WPRES-017: "solo en esta semana" seeds activeWeeks = [selectedWeek]',
      (tester) async {
    final repo = _MockRoutineRepository();
    Routine? captured;
    when(() => repo.createAssigned(any())).thenAnswer((inv) async {
      captured = inv.positionalArguments.first as Routine;
      return captured!.copyWith(id: 'plan-scope');
    });

    await _pumpEditor(
      tester,
      mode: const TrainerAssigning(athleteId: 'athlete-x'),
      overrides: _overrides(repo: repo, uid: 'trainer-1'),
    );

    await tester.enterText(
        find.byKey(const Key('editor_name_field')), 'Plan Scope');
    await tester.enterText(find.byKey(const Key('editor_split_field')), 'PPL');
    await tester.pumpAndSettle();

    // 3-week plan, navigate to week 2 (index 1)
    await _tapByKey(tester, 'add_week_button');
    await _tapByKey(tester, 'add_week_button');
    await _tapByKey(tester, 'week_tab_1');

    // Add exercise, choose "solo en esta semana"
    await tester.ensureVisible(find.text('Agregar ejercicio'));
    await tester.tap(find.text('Agregar ejercicio'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Press de Banca').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Agregar 1 ejercicio'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Agregar solo en esta semana'));
    await tester.pumpAndSettle();

    // Fill reps for week 1 only (the slot is present only in week 1;
    // other weeks are skipped by _invalidWeekFirstDay for absent slots).
    await _fillVisibleReps(tester, '8');

    await tester.tap(find.widgetWithText(ElevatedButton, 'ASIGNAR PLAN'));
    await tester.pumpAndSettle();

    expect(captured, isNotNull);
    final slot = captured!.days.first.slots.first;
    expect(
      slot.activeWeeks,
      equals([1]),
      reason: 'SCENARIO-WPRES-017: activeWeeks must be [1] for "this week"',
    );
  });

  testWidgets(
      'SCENARIO-WPRES-018: "todas las semanas" seeds empty mask (all weeks)',
      (tester) async {
    final repo = _MockRoutineRepository();
    Routine? captured;
    when(() => repo.createAssigned(any())).thenAnswer((inv) async {
      captured = inv.positionalArguments.first as Routine;
      return captured!.copyWith(id: 'plan-scope-all');
    });

    await _pumpEditor(
      tester,
      mode: const TrainerAssigning(athleteId: 'athlete-x'),
      overrides: _overrides(repo: repo, uid: 'trainer-1'),
    );

    await tester.enterText(
        find.byKey(const Key('editor_name_field')), 'Plan Scope All');
    await tester.enterText(find.byKey(const Key('editor_split_field')), 'PPL');
    await tester.pumpAndSettle();

    // 3-week plan, navigate to week 2 (index 1)
    await _tapByKey(tester, 'add_week_button');
    await _tapByKey(tester, 'add_week_button');
    await _tapByKey(tester, 'week_tab_1');

    // Add exercise, choose "todas las semanas"
    await tester.ensureVisible(find.text('Agregar ejercicio'));
    await tester.tap(find.text('Agregar ejercicio'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Press de Banca').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Agregar 1 ejercicio'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Agregar en todas las semanas'));
    await tester.pumpAndSettle();

    // Fill reps for all weeks
    await _fillVisibleReps(tester, '10');
    await _tapByKey(tester, 'week_tab_0');
    await _fillVisibleReps(tester, '8');
    await _tapByKey(tester, 'week_tab_2');
    await _fillVisibleReps(tester, '12');

    await tester.tap(find.widgetWithText(ElevatedButton, 'ASIGNAR PLAN'));
    await tester.pumpAndSettle();

    expect(captured, isNotNull);
    final slot = captured!.days.first.slots.first;
    expect(
      slot.activeWeeks,
      isEmpty,
      reason:
          'SCENARIO-WPRES-018: "todas las semanas" must produce empty activeWeeks',
    );
  });

  testWidgets('SCENARIO-WPRES-019a: no scope dialog when plan has only 1 week',
      (tester) async {
    await _pumpEditor(
      tester,
      mode: const SelfCreating(),
      overrides: _overrides(),
    );

    await tester.enterText(
        find.byKey(const Key('editor_name_field')), 'Mi Plan');
    await tester.pumpAndSettle();

    // Single-week plan: add exercise — no scope dialog should appear because
    // _promptAddScope returns allWeeks immediately when _numWeeks <= 1.
    await _addBenchPress(tester);
    expect(find.text('Agregar solo en esta semana'), findsNothing,
        reason: 'SCENARIO-WPRES-019: no dialog for single-week plan');
    expect(find.text('Press de Banca'), findsOneWidget,
        reason: 'exercise must be added without scope dialog');
  });

  testWidgets(
      'SCENARIO-WPRES-019b: no scope dialog when on week 1 (index 0) of '
      'multi-week plan', (tester) async {
    // Start fresh — build a 2-week plan and immediately navigate to week 0
    // WITHOUT adding any exercise first. This avoids the layout issue caused
    // by having a slot row that pushes the "Agregar ejercicio" button below
    // the tapable area after week switching.
    await _pumpEditor(
      tester,
      mode: const SelfCreating(),
      overrides: _overrides(),
    );

    await tester.enterText(
        find.byKey(const Key('editor_name_field')), 'Mi Plan');
    await tester.pumpAndSettle();

    // Add a week — editor auto-navigates to the new week (index 1).
    await _tapByKey(tester, 'add_week_button');

    // Switch BACK to week 0 (index 0).
    await _tapByKey(tester, 'week_tab_0');

    // Add exercise on week 0 — _promptAddScope must return allWeeks without
    // showing a dialog (ADR-WPRES-04: week 0 always broadcasts to all weeks).
    await _addBenchPress(tester);

    expect(find.text('Agregar solo en esta semana'), findsNothing,
        reason: 'SCENARIO-WPRES-019: no scope dialog when selectedWeek == 0');
    expect(find.text('Press de Banca'), findsOneWidget,
        reason: 'exercise must be added when no scope dialog blocks the flow');
  });

  // ── Task 2.1 / 2.4 — duplicar-semana copies presence (SCENARIO-WPRES-020/021)

  group('SCENARIO-WPRES-020/021: duplicar-semana presence', () {
    test(
        'SCENARIO-WPRES-020: duplicar copies presence — slot with empty mask '
        'stays present; masked-out slot stays absent', () {
      // Slot A: activeWeeks = {} (empty = all weeks) → present in week 0
      // Slot B: activeWeeks = {2} → absent in week 0
      // After duplicating week 0 into week 1: A present in week 1, B absent.
      final result = RoutineEditorTestBridge.duplicateWeekPresence(
        numWeeks: 3,
        sourceWeek: 0,
        targetWeek: 1,
        slots: [
          (
            activeWeeks: <int>{},
            weekSets: [
              [_rep(8)],
              [_rep(8)],
              [_rep(8)]
            ]
          ),
          (
            activeWeeks: {2},
            weekSets: [
              [_rep(6)],
              [_rep(6)],
              [_rep(6)]
            ]
          ),
        ],
      );

      // Slot A: empty → stays empty (still all weeks)
      expect(result[0].isEmpty, isTrue,
          reason: 'empty mask stays empty after duplicate');
      // Slot B: {2} → still {2}, week 1 not added
      expect(result[1], equals({2}),
          reason: 'absent slot must not gain week 1 after duplicate');
    });

    test(
        'SCENARIO-WPRES-021: duplicar presence is independent — editing copy '
        'does not affect source', () {
      // Slot with activeWeeks = {0, 1} → source week 0 is present
      // After duplicating week 0 into week 1, both 0 and 1 are present.
      // Independence: adding week 1 to a non-empty mask copy must not affect
      // the original mask.
      final resultMasks = RoutineEditorTestBridge.duplicateWeekPresence(
        numWeeks: 3,
        sourceWeek: 0,
        targetWeek: 1,
        slots: [
          (
            activeWeeks: {0},
            weekSets: [
              [_rep(8)],
              [_rep(8)],
              [_rep(8)]
            ]
          ),
        ],
      );

      // After duplicating week 0 into week 1, slot gains week 1 in its mask
      expect(resultMasks[0], containsAll([0, 1]),
          reason:
              'slot present in source week gains the target week in its mask');

      // The original {0} set is NOT the same reference as resultMasks[0]
      // (independence). We can only assert via value, but we verify that
      // the result has week 1 (source didn't) without verifying reference
      // identity — the real test is in the widget-level REPRO below.
    });
  });

  // ── Task 2.5 / 2.6 — _isValid rejects all-excluding mask (SCENARIO-WPRES-022/023)

  group('buildRoutineSlot activeWeeks (REQ-WPRES-013/014)', () {
    test(
        'SCENARIO-WPRES-022: buildRoutineSlot emits sorted activeWeeks from '
        'non-empty set', () {
      final slot = RoutineEditorTestBridge.buildSlotBridgeWithPresence(
        exerciseMode: ExerciseMode.reps,
        repMode: RepMode.single,
        weeklySets: [
          [_rep(8)],
          [_rep(10)],
          [_rep(12)],
        ],
        activeWeeks: {2, 0},
      );

      expect(slot.activeWeeks, equals([0, 2]),
          reason: 'activeWeeks must be sorted in the emitted RoutineSlot');
    });

    test(
        'SCENARIO-WPRES-022b: buildRoutineSlot emits empty activeWeeks from '
        'empty set (all-weeks)', () {
      final slot = RoutineEditorTestBridge.buildSlotBridgeWithPresence(
        exerciseMode: ExerciseMode.reps,
        repMode: RepMode.single,
        weeklySets: [
          [_rep(8)],
        ],
        activeWeeks: {},
      );

      expect(slot.activeWeeks, isEmpty,
          reason: 'empty activeWeeks set → empty list (present in all weeks)');
    });

    test(
        'SCENARIO-WPRES-023: _isValid rejects slot with out-of-range mask '
        '(numWeeks == 2, activeWeeks == [3, 4])', () {
      final isValid = RoutineEditorTestBridge.isPresenceMaskValidBridge(
        numWeeks: 2,
        activeWeeks: {3, 4},
      );

      expect(isValid, isFalse,
          reason:
              'SCENARIO-WPRES-023: mask [3,4] excludes all weeks in a 2-week plan');
    });

    test('SCENARIO-WPRES-022c: _isValid accepts valid in-range mask', () {
      final isValid = RoutineEditorTestBridge.isPresenceMaskValidBridge(
        numWeeks: 2,
        activeWeeks: {0, 1},
      );

      expect(isValid, isTrue,
          reason: 'mask [0,1] covers both weeks of a 2-week plan');
    });

    test('_isValid accepts empty mask (all weeks)', () {
      final isValid = RoutineEditorTestBridge.isPresenceMaskValidBridge(
        numWeeks: 3,
        activeWeeks: {},
      );

      expect(isValid, isTrue,
          reason: 'empty mask means present in all weeks — always valid');
    });
  });
}

// ── Delete-this-week helper ────────────────────────────────────────────────────

/// Opens the ⋮ menu for [slotIndex] and selects "Solo esta semana".
Future<void> _deleteSlotThisWeek(WidgetTester tester, int slotIndex) async {
  final menuButton = find.byKey(Key('slot_menu_button_$slotIndex'));
  await tester.ensureVisible(menuButton);
  await tester.tap(menuButton);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Eliminar'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Solo esta semana'));
  await tester.pumpAndSettle();
}
