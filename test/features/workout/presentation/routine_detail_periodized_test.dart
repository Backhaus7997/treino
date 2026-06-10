// Tests 3.15, 3.16, 3.17
// SCENARIO-031/032/035/036/038 — periodized plan gating affordances in
// routine_detail_screen.dart.
//
// HARD INVARIANT (REQ-PERIOD-042): single-week routines MUST render
// exactly today's behavior — no week selector, no locks, any day startable.
//
// Strategy: override sessionsByUidProvider (String key → structural equality)
// so planProgressProvider can compute naturally without key equality issues.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
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
        'SCENARIO-031/032: locked day shows BLOQUEADO text (day 2 locked, no completions)',
        (tester) async {
      final routine = _multiWeekRoutine(
        numWeeks: 2,
        days: [_day(1), _day(2)],
      );
      // No sessions → no completions → day 2 is locked (day 1 not done)
      await tester.pumpWidget(_wrap(
        RoutineDetailScreen(routineId: routine.id),
        routine: routine,
      ));
      await _settle(tester);

      // Tap the "DÍA 2" chip — chips are below the hero in the scroll view;
      // use skipOffstage: false because they may be outside the viewport.
      await tester.tap(find.text('DÍA 2', skipOffstage: false));
      await _settle(tester);

      // With no completions, day 2 is locked (day 1 not done)
      expect(find.textContaining('BLOQUEADO', skipOffstage: false),
          findsOneWidget);
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
        'SCENARIO-036: plan-complete banner shown when all weeks/days done',
        (tester) async {
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
    });

    testWidgets(
        'SCENARIO-035: completed day shows COMPLETADO state (not EMPEZAR)',
        (tester) async {
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

      // Day 1 is done → COMPLETADO (not EMPEZAR). CTA is below the fold.
      expect(find.text('COMPLETADO', skipOffstage: false), findsOneWidget);
      expect(find.text('EMPEZAR', skipOffstage: false), findsNothing);
    });
  });
}
