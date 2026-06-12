// Tests 3.19
// SCENARIO-039: ExerciseSlotRow shows week 1 prescription when viewedWeek=1
// SCENARIO-040: ExerciseSlotRow shows fallback for single-week slot (weeklySets empty)
// SCENARIO-F01..F04: failure set display in _setsRepsSummary

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/workout/domain/routine_slot.dart';
import 'package:treino/features/workout/domain/set_enums.dart';
import 'package:treino/features/workout/domain/set_spec.dart';
import 'package:treino/features/workout/presentation/widgets/exercise_slot_row.dart';

Widget _wrap(Widget w) => MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(body: w),
    );

RoutineSlot _makeMultiWeekSlot() => const RoutineSlot(
      exerciseId: 'bench',
      exerciseName: 'Press de Banca',
      muscleGroup: 'Pecho',
      targetSets: 3,
      targetRepsMin: 8,
      targetRepsMax: 12,
      restSeconds: 90,
      weeklySets: [
        // Week 0: 3 sets of 8 reps
        [SetSpec(reps: 8), SetSpec(reps: 8), SetSpec(reps: 8)],
        // Week 1: 4 sets of 10 reps
        [
          SetSpec(reps: 10),
          SetSpec(reps: 10),
          SetSpec(reps: 10),
          SetSpec(reps: 10)
        ],
      ],
    );

RoutineSlot _makeSingleWeekSlot() => const RoutineSlot(
      exerciseId: 'squat',
      exerciseName: 'Sentadilla',
      muscleGroup: 'Piernas',
      targetSets: 4,
      targetRepsMin: 6,
      targetRepsMax: 10,
      restSeconds: 120,
      // weeklySets is empty → legacy fallback
    );

void main() {
  group('ExerciseSlotRow — week-aware prescription', () {
    // SCENARIO-039: week 0 shows 3 sets of 8 reps
    testWidgets('SCENARIO-039a: week=0 shows 3 · 8 (from weeklySets[0])',
        (tester) async {
      await tester.pumpWidget(_wrap(
        ExerciseSlotRow(
          slot: _makeMultiWeekSlot(),
          index: 1,
          week: 0,
          onTap: () {},
        ),
      ));
      expect(find.text('3 · 8'), findsOneWidget);
    });

    // SCENARIO-039: week 1 shows 4 sets of 10 reps
    testWidgets('SCENARIO-039b: week=1 shows 4 · 10 (from weeklySets[1])',
        (tester) async {
      await tester.pumpWidget(_wrap(
        ExerciseSlotRow(
          slot: _makeMultiWeekSlot(),
          index: 1,
          week: 1,
          onTap: () {},
        ),
      ));
      expect(find.text('4 · 10'), findsOneWidget);
    });

    // SCENARIO-040: legacy fallback when weeklySets empty
    testWidgets(
        'SCENARIO-040: weeklySets empty → falls back to legacy targetSets·targetRepsMin–Max',
        (tester) async {
      await tester.pumpWidget(_wrap(
        ExerciseSlotRow(
          slot: _makeSingleWeekSlot(),
          index: 1,
          week: 0,
          onTap: () {},
        ),
      ));
      // Legacy fallback: targetSets=4, targetRepsMin=6, targetRepsMax=10
      expect(find.text('4 · 6–10'), findsOneWidget);
    });

    // Default week=0 param maintains backward compat
    testWidgets('default week=0 param renders correctly for single-week slot',
        (tester) async {
      await tester.pumpWidget(_wrap(
        ExerciseSlotRow(
          slot: _makeSingleWeekSlot(),
          index: 2,
          onTap: () {},
          // week not specified → defaults to 0
        ),
      ));
      expect(find.text('4 · 6–10'), findsOneWidget);
    });

    // Out-of-range week falls back to legacy (no throw)
    testWidgets('out-of-range week falls back to legacy (no exception)',
        (tester) async {
      await tester.pumpWidget(_wrap(
        ExerciseSlotRow(
          slot: _makeMultiWeekSlot(),
          index: 1,
          week: 99, // out of range
          onTap: () {},
        ),
      ));
      // effectiveSetsForWeek(99) falls back to effectiveSets (legacy)
      // For this slot, sets is empty and targetRepsMin/Max = 8/12, targetSets=3
      expect(tester.takeException(), isNull);
      // Should render something meaningful (legacy fallback)
      expect(find.byType(ExerciseSlotRow), findsOneWidget);
    });
  });

  // ── Failure set display (SCENARIO-F01..F04) ────────────────────────────────

  group('ExerciseSlotRow — failure set summary', () {
    RoutineSlot makeFailureSlot({int failureSets = 3}) => RoutineSlot(
          exerciseId: 'pull-up',
          exerciseName: 'Dominadas',
          muscleGroup: 'Espalda',
          targetSets: failureSets,
          targetRepsMin: 4,
          targetRepsMax: 10,
          restSeconds: 90,
          weeklySets: [
            List.generate(
              failureSets,
              (_) => const SetSpec(type: SetType.failure),
            ),
          ],
        );

    RoutineSlot makeMixedSlot() => const RoutineSlot(
          exerciseId: 'pull-up',
          exerciseName: 'Dominadas',
          muscleGroup: 'Espalda',
          targetSets: 3,
          targetRepsMin: 8,
          targetRepsMax: 10,
          restSeconds: 90,
          weeklySets: [
            [
              SetSpec(reps: 8),
              SetSpec(reps: 8),
              SetSpec(type: SetType.failure),
            ],
          ],
        );

    testWidgets('SCENARIO-F01: all-failure slot shows "<N> · Al fallo"',
        (tester) async {
      await tester.pumpWidget(_wrap(
        ExerciseSlotRow(
          slot: makeFailureSlot(failureSets: 3),
          index: 1,
          onTap: () {},
        ),
      ));
      expect(find.text('3 · Al fallo'), findsOneWidget);
    });

    testWidgets('SCENARIO-F02: single failure set shows "1 · Al fallo"',
        (tester) async {
      await tester.pumpWidget(_wrap(
        ExerciseSlotRow(
          slot: makeFailureSlot(failureSets: 1),
          index: 1,
          onTap: () {},
        ),
      ));
      expect(find.text('1 · Al fallo'), findsOneWidget);
    });

    testWidgets(
        'SCENARIO-F03: mixed sets show normal sets + failure count separated by " + "',
        (tester) async {
      await tester.pumpWidget(_wrap(
        ExerciseSlotRow(
          slot: makeMixedSlot(),
          index: 1,
          onTap: () {},
        ),
      ));
      // 2 normal sets of 8 + 1 failure
      expect(find.text('2 · 8 + 1 · Al fallo'), findsOneWidget);
    });

    testWidgets(
        'SCENARIO-F04: legacy slot with targetRepsMin/Max ignores failure type '
        '(no weeklySets — legacy path unaffected)', (tester) async {
      // Legacy slot: no weeklySets, no sets — falls back to targetRepsMin/Max.
      // The legacy path doesn't have SetType info, so it renders the range.
      const legacySlot = RoutineSlot(
        exerciseId: 'pull-up',
        exerciseName: 'Dominadas',
        muscleGroup: 'Espalda',
        targetSets: 4,
        targetRepsMin: 4,
        targetRepsMax: 10,
        restSeconds: 90,
      );
      await tester.pumpWidget(_wrap(
        ExerciseSlotRow(
          slot: legacySlot,
          index: 1,
          onTap: () {},
        ),
      ));
      expect(find.text('4 · 4–10'), findsOneWidget);
    });
  });
}
