// Tests 3.19
// SCENARIO-039: ExerciseSlotRow shows week 1 prescription when viewedWeek=1
// SCENARIO-040: ExerciseSlotRow shows fallback for single-week slot (weeklySets empty)

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/workout/domain/routine_slot.dart';
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
}
