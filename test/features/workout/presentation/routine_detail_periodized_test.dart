// Tests 3.15, 3.16, 3.17
// SCENARIO-031/032/035/036/038 — periodized plan gating affordances in
// routine_detail_screen.dart.
//
// HARD INVARIANT (REQ-PERIOD-042): single-week routines MUST render
// exactly today's behavior — no week selector, no locks, any day startable.
//
// Strategy: override sessionsByUidProvider (String key → structural equality)
// so planProgressProvider can compute naturally without key equality issues.
//
// Phase 3 additions (SCENARIO-WPRES-024..028):
// REQ-WPRES-020 — filter slots by isPresentInWeek(viewedWeek) in detail screen
// REQ-WPRES-015 — numWeeks==1 invariant: no filtering applied

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/l10n/app_l10n.dart';
import 'package:treino/features/profile/application/user_providers.dart'
    show userProfileProvider;
import 'package:treino/features/profile/domain/experience_level.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';
import 'package:treino/features/workout/application/routine_providers.dart';
import 'package:treino/features/workout/application/session_providers.dart'
    show currentUidProvider, sessionsByUidProvider;
import 'package:treino/features/workout/domain/routine.dart';
import 'package:treino/features/workout/domain/routine_day.dart';
import 'package:treino/features/workout/domain/routine_slot.dart';
import 'package:treino/features/workout/domain/session.dart';
import 'package:treino/features/workout/domain/session_status.dart';
import 'package:treino/features/workout/presentation/routine_detail_screen.dart';
import 'package:treino/features/workout/presentation/widgets/exercise_slot_row.dart';

// ── Test helpers ────────────────────────────────────────────────────────────

const _uid = 'u1';

UserProfile _athleteProfile() => UserProfile(
      uid: _uid,
      email: 'u1@test.com',
      displayName: 'Atleta',
      role: UserRole.athlete,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

/// Makes a finished+fullyCompleted session for the given week+day combination.
Session _doneSession({
  required String routineId,
  required int week,
  required int day,
  int seq = 0,
}) =>
    Session(
      id: 'sess-w${week}d$day-$seq',
      uid: _uid,
      routineId: routineId,
      routineName: 'Plan',
      startedAt: DateTime.utc(2026, 1, week + 1, day),
      finishedAt: DateTime.utc(2026, 1, week + 1, day, 1),
      status: SessionStatus.finished,
      dayNumber: day,
      weekNumber: week,
      wasFullyCompleted: true,
    );

RoutineSlot _slot({
  String exerciseId = 'bench',
  String exerciseName = 'Press de Banca',
  int targetSets = 3,
}) =>
    RoutineSlot(
      exerciseId: exerciseId,
      exerciseName: exerciseName,
      muscleGroup: 'Pecho',
      targetSets: targetSets,
      targetRepsMin: 8,
      targetRepsMax: 12,
      restSeconds: 90,
    );

RoutineDay _day(int number, {String name = 'Push', List<RoutineSlot>? slots}) =>
    RoutineDay(
      dayNumber: number,
      name: name,
      slots: slots ?? [_slot()],
    );

Routine _multiWeekRoutine({
  int numWeeks = 2,
  List<RoutineDay>? days,
}) =>
    Routine(
      id: 'routine-p',
      name: 'Plan Periodizado',
      level: ExperienceLevel.intermediate,
      days: days ?? [_day(1), _day(2), _day(3)],
      numWeeks: numWeeks,
    );

Routine _singleWeekRoutine({List<RoutineDay>? days}) => Routine(
      id: 'routine-s',
      name: 'Rutina Simple',
      level: ExperienceLevel.beginner,
      days: days ?? [_day(1), _day(2)],
      numWeeks: 1,
    );

/// Wraps under ProviderScope with required overrides.
/// Uses sessionsByUidProvider (String key, structural equality) so
/// planProgressProvider can compute without key-equality problems.
Widget _wrap(
  Widget w, {
  required Routine routine,
  List<Session> sessions = const [],
}) {
  return ProviderScope(
    overrides: [
      routineByIdProvider(routine.id).overrideWith((ref) async => routine),
      currentUidProvider.overrideWithValue(_uid),
      userProfileProvider
          .overrideWith((ref) => Stream.value(_athleteProfile())),
      sessionsByUidProvider(_uid).overrideWith((ref) async => sessions),
    ],
    child: MaterialApp(
      theme: AppTheme.dark(),
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      locale: const Locale('es', 'AR'),
      home: Scaffold(body: w),
    ),
  );
}

/// Pumps until async providers settle.
/// planProgressProvider chains routineByIdProvider → sessionsByUidProvider
/// → derivePlanProgress, so we need enough pumps for all three futures to
/// resolve plus the stream to emit the user profile.
Future<void> _settle(WidgetTester tester) async {
  // Round 1 – drain the initial microtask queue.
  await tester.pump();
  // Round 2 – routineByIdProvider future resolves.
  await tester.pump(const Duration(milliseconds: 50));
  // Round 3 – sessionsByUidProvider resolves inside planProgressProvider.
  await tester.pump(const Duration(milliseconds: 50));
  // Round 4 – planProgressProvider data triggers rebuild.
  await tester.pump(const Duration(milliseconds: 50));
  // Round 5 – stream (userProfileProvider) and any remaining rebuilds.
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  // ── Test 3.17 — SCENARIO-038 HARD INVARIANT ─────────────────────────────

  group('SCENARIO-038 — single-week routine (numWeeks=1) HARD INVARIANT', () {
    testWidgets('no week selector rendered for single-week routine',
        (tester) async {
      final routine = _singleWeekRoutine();
      await tester.pumpWidget(_wrap(
        RoutineDetailScreen(routineId: routine.id),
        routine: routine,
      ));
      await _settle(tester);

      // ChoiceChips only from the day selector (2 days) — no "SEM N" chips
      final chips = tester.widgetList<ChoiceChip>(find.byType(ChoiceChip));
      final semChips = chips.where((c) {
        final label = c.label;
        if (label is Text) return (label.data ?? '').startsWith('SEM');
        return false;
      }).toList();
      expect(semChips, isEmpty, reason: 'No SEM chips for single-week routine');
    });

    testWidgets('no lock affordance for single-week routine', (tester) async {
      final routine = _singleWeekRoutine();
      await tester.pumpWidget(_wrap(
        RoutineDetailScreen(routineId: routine.id),
        routine: routine,
      ));
      await _settle(tester);

      expect(
        find.textContaining('BLOQUEADO', skipOffstage: false),
        findsNothing,
      );
      expect(
        find.textContaining('BLOQUEADA', skipOffstage: false),
        findsNothing,
      );
    });

    testWidgets('EMPEZAR button is present and enabled for single-week routine',
        (tester) async {
      final routine = _singleWeekRoutine();
      await tester.pumpWidget(_wrap(
        RoutineDetailScreen(routineId: routine.id),
        routine: routine,
      ));
      await _settle(tester);

      // The CTA bar may be scrolled off-screen in the test viewport; use
      // skipOffstage: false to find it even when not in the visible area.
      expect(find.text('EMPEZAR', skipOffstage: false), findsOneWidget);
      final btn = tester.widget<ElevatedButton>(
          find.widgetWithText(ElevatedButton, 'EMPEZAR', skipOffstage: false));
      expect(btn.onPressed, isNotNull);
    });

    testWidgets('ExerciseSlotRow renders for every slot (no changes to slots)',
        (tester) async {
      final routine = _singleWeekRoutine(
        days: [
          _day(1, slots: [_slot(), _slot(exerciseId: 'squat')])
        ],
      );
      await tester.pumpWidget(_wrap(
        RoutineDetailScreen(routineId: routine.id),
        routine: routine,
      ));
      await _settle(tester);
      expect(find.byType(ExerciseSlotRow), findsNWidgets(2));
    });

    // Fix 3 — REQ-PERIOD-042 "ANY day startable" on single-week plan
    testWidgets(
        'SCENARIO-038 fix: DÍA 2 tap on single-week routine → EMPEZAR enabled, no lock affordance',
        (tester) async {
      // _singleWeekRoutine() has 2 days (day 1 + day 2).
      final routine = _singleWeekRoutine();
      await tester.pumpWidget(_wrap(
        RoutineDetailScreen(routineId: routine.id),
        routine: routine,
      ));
      await _settle(tester);

      // Tap the second day chip; chips may be below the fold.
      await tester.tap(find.text('DÍA 2', skipOffstage: false));
      await _settle(tester);

      // EMPEZAR must be present and its button enabled (onPressed != null).
      expect(find.text('EMPEZAR', skipOffstage: false), findsOneWidget);
      final btn = tester.widget<ElevatedButton>(
          find.widgetWithText(ElevatedButton, 'EMPEZAR', skipOffstage: false));
      expect(btn.onPressed, isNotNull,
          reason: 'Day 2 on a single-week plan must be startable');

      // No lock affordances.
      expect(
        find.textContaining('BLOQUEADO', skipOffstage: false),
        findsNothing,
      );
      expect(
        find.textContaining('SEMANA BLOQUEADA', skipOffstage: false),
        findsNothing,
      );
    });
  });

  // ── Tests 3.15/3.16 — Periodized plan affordances ───────────────────────

  group('Periodized plan (numWeeks > 1) affordances', () {
    testWidgets('SCENARIO-031: week selector "SEM 1" / "SEM 2" rendered',
        (tester) async {
      final routine = _multiWeekRoutine(numWeeks: 2);
      await tester.pumpWidget(_wrap(
        RoutineDetailScreen(routineId: routine.id),
        routine: routine,
      ));
      await _settle(tester);

      final chips = tester.widgetList<ChoiceChip>(find.byType(ChoiceChip));
      final semChips = chips.where((c) {
        final label = c.label;
        if (label is Text) return (label.data ?? '').startsWith('SEM');
        return false;
      }).toList();
      expect(semChips.length, equals(2),
          reason: 'Two SEM chips for 2-week plan');
    });

    testWidgets(
        'A1 (2026-06-29): day 2 of a periodized plan with no prior progress '
        'is NO LONGER locked — athlete may jump in directly', (tester) async {
      // Pre-A1 (SCENARIO-031/032) this opened to "DÍA BLOQUEADO" because day 1
      // was not finished. Decision A1 dropped the sequential lock — every day
      // is freely accessible, so the screen must show the EMPEZAR affordance
      // instead of any BLOQUEADO badge.
      final routine = _multiWeekRoutine(
        numWeeks: 2,
        days: [_day(1), _day(2)],
      );
      await tester.pumpWidget(_wrap(
        RoutineDetailScreen(routineId: routine.id),
        routine: routine,
      ));
      await _settle(tester);

      // Tap the "DÍA 2" chip — chips are below the hero in the scroll view;
      // use skipOffstage: false because they may be outside the viewport.
      await tester.tap(find.text('DÍA 2', skipOffstage: false));
      await _settle(tester);

      expect(
        find.textContaining('BLOQUEADO', skipOffstage: false),
        findsNothing,
        reason: 'A1 removed the sequential day lock — no BLOQUEADO badge',
      );
      expect(
        find.textContaining('BLOQUEADA', skipOffstage: false),
        findsNothing,
        reason: 'A1 also removed the sequential week lock',
      );
    });

    testWidgets(
        'SCENARIO-035: startable day shows EMPEZAR CTA (day 1, week 0, no completions)',
        (tester) async {
      final routine = _multiWeekRoutine(numWeeks: 2, days: [_day(1), _day(2)]);
      await tester.pumpWidget(_wrap(
        RoutineDetailScreen(routineId: routine.id),
        routine: routine,
      ));
      await _settle(tester);

      // Day 1 of week 0 should be startable (no completions needed).
      // CTA bar is below the fold in the test viewport → skipOffstage: false.
      expect(find.text('EMPEZAR', skipOffstage: false), findsOneWidget);
    });

    testWidgets(
        'SCENARIO-REPEAT-001: plan-complete banner shown when all weeks/days '
        'done, AND REPETIR remains available (device repro, extends '
        'SCENARIO-036)', (tester) async {
      final routine = _multiWeekRoutine(
        numWeeks: 2,
        days: [_day(1), _day(2)],
      );
      // All sessions done for both weeks
      final sessions = [
        _doneSession(routineId: routine.id, week: 0, day: 1),
        _doneSession(routineId: routine.id, week: 0, day: 2),
        _doneSession(routineId: routine.id, week: 1, day: 1),
        _doneSession(routineId: routine.id, week: 1, day: 2),
      ];
      await tester.pumpWidget(_wrap(
        RoutineDetailScreen(routineId: routine.id),
        routine: routine,
        sessions: sessions,
      ));
      await _settle(tester);

      // Plan-complete banner is in the CTA area below the fold.
      expect(find.text('PLAN COMPLETADO', skipOffstage: false), findsOneWidget);
      // AD-2: the banner is a signal, never a lock — REPETIR must still be
      // there and enabled. This is the true device repro path: before this
      // change, the widget early-returned the banner with no button at all.
      expect(
        find.text('REPETIR', skipOffstage: false),
        findsOneWidget,
        reason: 'A complete plan must still offer an action (AD-2) — the '
            'device repro this change fixes.',
      );
      // AD-1: banner XOR chip. Exact match on 'COMPLETADO' does not collide
      // with 'PLAN COMPLETADO' (find.text is an exact match, not substring).
      expect(
        find.text('COMPLETADO', skipOffstage: false),
        findsNothing,
        reason: 'Banner XOR chip (AD-1) — PLAN COMPLETADO already states '
            'the day-level fact; stacking COMPLETADO would say it twice.',
      );
      final btn = tester.widget<ElevatedButton>(find
          .ancestor(
            of: find.text('REPETIR', skipOffstage: false),
            matching: find.byType(ElevatedButton, skipOffstage: false),
          )
          .first);
      expect(btn.onPressed, isNotNull);
    });

    testWidgets(
        'SCENARIO-REPEAT-003: completed day shows COMPLETADO + REPETIR '
        '(renegotiates SCENARIO-035, plan incomplete)', (tester) async {
      final routine = _multiWeekRoutine(
        numWeeks: 2,
        days: [_day(1), _day(2)],
      );
      // Day 1 of week 0 is already completed
      final sessions = [
        _doneSession(routineId: routine.id, week: 0, day: 1),
      ];
      await tester.pumpWidget(_wrap(
        RoutineDetailScreen(routineId: routine.id),
        routine: routine,
        sessions: sessions,
      ));
      await _settle(tester);

      // Day 1 is done → COMPLETADO chip + REPETIR button, never EMPEZAR.
      expect(find.text('COMPLETADO', skipOffstage: false), findsOneWidget);
      expect(find.text('REPETIR', skipOffstage: false), findsOneWidget);
      expect(
        find.text('EMPEZAR', skipOffstage: false),
        findsNothing,
        reason: 'Completion relabels the action to REPETIR — it never '
            'removes it (AD-2). This is NOT "there is no action".',
      );
      final btn = tester.widget<ElevatedButton>(find
          .ancestor(
            of: find.text('REPETIR', skipOffstage: false),
            matching: find.byType(ElevatedButton, skipOffstage: false),
          )
          .first);
      expect(btn.onPressed, isNotNull,
          reason: 'Completion is a signal, never a hard lock (AD-2).');
    });
  });

  // ── T-4 — AD-2 invariant: completion never removes the action ──────────
  // Replaces the 14 plan_gating.dart tests deleted in Phase 2 (AD-3): those
  // asserted a function returned a literal; these assert the action EXISTS
  // and is enabled, which is strictly stronger.
  group('AD-2 invariant — completion never removes the action', () {
    testWidgets('fresh day (no completions): enabled action button renders',
        (tester) async {
      final routine = _multiWeekRoutine(numWeeks: 2, days: [_day(1), _day(2)]);
      await tester.pumpWidget(_wrap(
        RoutineDetailScreen(routineId: routine.id),
        routine: routine,
      ));
      await _settle(tester);

      final btn = tester.widget<ElevatedButton>(find
          .ancestor(
            of: find.text('EMPEZAR', skipOffstage: false),
            matching: find.byType(ElevatedButton, skipOffstage: false),
          )
          .first);
      expect(btn.onPressed, isNotNull);
    });

    testWidgets(
        'day already done (plan incomplete): enabled action button renders',
        (tester) async {
      final routine = _multiWeekRoutine(numWeeks: 2, days: [_day(1), _day(2)]);
      final sessions = [
        _doneSession(routineId: routine.id, week: 0, day: 1),
      ];
      await tester.pumpWidget(_wrap(
        RoutineDetailScreen(routineId: routine.id),
        routine: routine,
        sessions: sessions,
      ));
      await _settle(tester);

      final btn = tester.widget<ElevatedButton>(find
          .ancestor(
            of: find.text('REPETIR', skipOffstage: false),
            matching: find.byType(ElevatedButton, skipOffstage: false),
          )
          .first);
      expect(btn.onPressed, isNotNull);
    });

    testWidgets(
        'plan complete: enabled action button renders (not just the banner)',
        (tester) async {
      final routine = _multiWeekRoutine(numWeeks: 2, days: [_day(1), _day(2)]);
      final sessions = [
        _doneSession(routineId: routine.id, week: 0, day: 1),
        _doneSession(routineId: routine.id, week: 0, day: 2),
        _doneSession(routineId: routine.id, week: 1, day: 1),
        _doneSession(routineId: routine.id, week: 1, day: 2),
      ];
      await tester.pumpWidget(_wrap(
        RoutineDetailScreen(routineId: routine.id),
        routine: routine,
        sessions: sessions,
      ));
      await _settle(tester);

      final btn = tester.widget<ElevatedButton>(find
          .ancestor(
            of: find.text('REPETIR', skipOffstage: false),
            matching: find.byType(ElevatedButton, skipOffstage: false),
          )
          .first);
      expect(btn.onPressed, isNotNull,
          reason: 'AD-2: completion is a signal, never a hard lock — this '
              'replaces the 14 plan_gating.dart tests deleted by AD-3.');
    });
  });

  // ── Phase 3: REQ-WPRES-015 / REQ-WPRES-020 — presence filter in detail ─────

  group('SCENARIO-WPRES-024 — numWeeks==1 no presence filter applied', () {
    testWidgets(
        'SCENARIO-WPRES-024: single-week plan renders all slots, no filtering',
        (tester) async {
      // Slot with activeWeeks=[] (present everywhere, but single-week: must not filter)
      final slotA = _slot(exerciseId: 'benchA', exerciseName: 'Press Banca');
      final slotB = _slot(exerciseId: 'squat', exerciseName: 'Sentadilla');
      final routine = _singleWeekRoutine(
        days: [
          _day(1, slots: [slotA, slotB])
        ],
      );
      await tester.pumpWidget(_wrap(
        RoutineDetailScreen(routineId: routine.id),
        routine: routine,
      ));
      await _settle(tester);

      // Both slots must render — no filtering on single-week plan
      expect(find.byType(ExerciseSlotRow), findsNWidgets(2));
    });
  });

  group('SCENARIO-WPRES-026..028 — presence filter in multi-week detail', () {
    // A slot with activeWeeks == [] is present in ALL weeks (empty = all).
    // A slot with activeWeeks == [2] is present ONLY in week index 2.
    RoutineSlot slotPresentAllWeeks({required String exerciseId}) =>
        RoutineSlot(
          exerciseId: exerciseId,
          exerciseName: 'Ejercicio $exerciseId',
          muscleGroup: 'Pecho',
          targetSets: 3,
          targetRepsMin: 8,
          targetRepsMax: 12,
          restSeconds: 90,
          // activeWeeks: [] (default) → present in all weeks
        );

    RoutineSlot slotPresentOnlyWeek2({required String exerciseId}) =>
        RoutineSlot(
          exerciseId: exerciseId,
          exerciseName: 'Ejercicio $exerciseId',
          muscleGroup: 'Espalda',
          targetSets: 3,
          targetRepsMin: 8,
          targetRepsMax: 12,
          restSeconds: 90,
          activeWeeks: const [2], // only week index 2
        );

    testWidgets(
        'SCENARIO-WPRES-026: detail shows only present slots for viewed week 0',
        (tester) async {
      final slotA = slotPresentAllWeeks(exerciseId: 'slotA');
      final slotB = slotPresentOnlyWeek2(exerciseId: 'slotB');
      // 3-week plan, day with both slots
      final routine = Routine(
        id: 'routine-3w-026',
        name: 'Plan 3 semanas',
        level: ExperienceLevel.intermediate,
        days: [
          RoutineDay(
            dayNumber: 1,
            name: 'Push',
            slots: [slotA, slotB],
          )
        ],
        numWeeks: 3,
      );
      await tester.pumpWidget(_wrap(
        RoutineDetailScreen(routineId: routine.id),
        routine: routine,
      ));
      await _settle(tester);

      // Week 0 is selected by default. slotA (activeWeeks=[]) is present.
      // slotB (activeWeeks=[2]) is NOT present in week 0 → must not render.
      expect(find.byType(ExerciseSlotRow), findsOneWidget,
          reason: 'Only slotA visible on week 0');
    });

    testWidgets('SCENARIO-WPRES-027: switching to week 2 shows both slots',
        (tester) async {
      final slotA = slotPresentAllWeeks(exerciseId: 'slotA');
      final slotB = slotPresentOnlyWeek2(exerciseId: 'slotB');
      // Use a distinct id from WPRES-026 to avoid provider cache overlap.
      final routine = Routine(
        id: 'routine-3w-027',
        name: 'Plan 3 semanas',
        level: ExperienceLevel.intermediate,
        days: [
          RoutineDay(
            dayNumber: 1,
            name: 'Push',
            slots: [slotA, slotB],
          )
        ],
        numWeeks: 3,
      );
      await tester.pumpWidget(_wrap(
        RoutineDetailScreen(routineId: routine.id),
        routine: routine,
      ));
      await _settle(tester);

      // Scroll to and tap "SEM 3" (index 2) to switch to week 2.
      final sem3Finder = find.text('SEM 3', skipOffstage: false);
      await tester.ensureVisible(sem3Finder);
      await tester.tap(sem3Finder);
      // One pump for setState + one settle for providers.
      await tester.pump();
      await _settle(tester);

      // Week 2 selected: both slots present (slotA=[], slotB=[2])
      expect(find.byType(ExerciseSlotRow), findsNWidgets(2),
          reason: 'Both slots visible on week 2');
    });

    testWidgets(
        'SCENARIO-WPRES-028: day where all slots excluded shows info message',
        (tester) async {
      // A slot present ONLY in week 2
      final slotOnlyWeek2 = slotPresentOnlyWeek2(exerciseId: 'slotOnlyW2');
      final routine = Routine(
        id: 'routine-3w-empty',
        name: 'Plan 3 semanas',
        level: ExperienceLevel.intermediate,
        days: [
          RoutineDay(
            dayNumber: 1,
            name: 'Push',
            slots: [slotOnlyWeek2],
          )
        ],
        numWeeks: 3,
      );
      await tester.pumpWidget(_wrap(
        RoutineDetailScreen(routineId: routine.id),
        routine: routine,
      ));
      await _settle(tester);

      // Week 0 selected by default. slotOnlyWeek2 is NOT present in week 0.
      // Filtered list is empty → must show "Sin ejercicios esta semana" message.
      expect(find.textContaining('Sin ejercicios', skipOffstage: false),
          findsOneWidget,
          reason: 'Info message shown when no slots present in this week');
      expect(find.byType(ExerciseSlotRow), findsNothing,
          reason: 'No ExerciseSlotRow when day has zero present slots');
    });

    testWidgets(
        'SCENARIO-REPEAT-002: plan complete + viewed day auto-satisfied '
        '(zero present slots that week) → EMPEZAR, not REPETIR',
        (tester) async {
      final slotA = slotPresentAllWeeks(exerciseId: 'slotA');
      final slotB = slotPresentOnlyWeek2(exerciseId: 'slotB');
      final routine = Routine(
        id: 'routine-3w-repeat-002',
        name: 'Plan 3 semanas',
        level: ExperienceLevel.intermediate,
        days: [
          RoutineDay(dayNumber: 1, name: 'Push', slots: [slotA]),
          RoutineDay(dayNumber: 2, name: 'Pull', slots: [slotB]),
        ],
        numWeeks: 3,
      );
      // Every REQUIRED (week, day) pair done: day1 is present every week
      // (0,1,2); day2 is present ONLY week index 2 (activeWeeks: [2]) → the
      // (week 0, day 2) pair is auto-satisfied (REQ-WPRES-022) and never
      // enters `completed`.
      final sessions = [
        _doneSession(routineId: routine.id, week: 0, day: 1),
        _doneSession(routineId: routine.id, week: 1, day: 1),
        _doneSession(routineId: routine.id, week: 2, day: 1),
        _doneSession(routineId: routine.id, week: 2, day: 2),
      ];
      await tester.pumpWidget(_wrap(
        RoutineDetailScreen(routineId: routine.id),
        routine: routine,
        sessions: sessions,
      ));
      await _settle(tester);

      // View day 2 of week 0 — auto-satisfied, never completed, while the
      // plan as a whole is complete.
      await tester.tap(find.text('DÍA 2', skipOffstage: false));
      await _settle(tester);

      expect(find.text('PLAN COMPLETADO', skipOffstage: false), findsOneWidget,
          reason: 'planComplete is true — every required pair is satisfied.');
      expect(
        find.text('EMPEZAR', skipOffstage: false),
        findsOneWidget,
        reason: 'This (week, day) was never in `completed` (zero present '
            'slots this week, REQ-WPRES-022) — the label rule is keyed off '
            'the DAY, not the plan (AD-5).',
      );
      expect(find.text('REPETIR', skipOffstage: false), findsNothing);
      final btn = tester.widget<ElevatedButton>(find
          .ancestor(
            of: find.text('EMPEZAR', skipOffstage: false),
            matching: find.byType(ElevatedButton, skipOffstage: false),
          )
          .first);
      expect(btn.onPressed, isNotNull);
    });
  });
}
