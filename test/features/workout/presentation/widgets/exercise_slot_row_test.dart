import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/workout/domain/routine_slot.dart';
import 'package:treino/features/workout/presentation/widgets/exercise_slot_row.dart';

Widget _wrap(Widget w) => MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(body: w),
    );

RoutineSlot _makeSlot({
  String exerciseId = 'bench-press',
  String exerciseName = 'Press de Banca',
  String muscleGroup = 'Pecho',
  int targetSets = 4,
  int targetRepsMin = 8,
  int targetRepsMax = 12,
  int restSeconds = 90,
}) =>
    RoutineSlot(
      exerciseId: exerciseId,
      exerciseName: exerciseName,
      muscleGroup: muscleGroup,
      targetSets: targetSets,
      targetRepsMin: targetRepsMin,
      targetRepsMax: targetRepsMax,
      restSeconds: restSeconds,
    );

void main() {
  group('ExerciseSlotRow', () {
    testWidgets(
        'SCENARIO-088: renders exercise name, sets·reps, and muscle group',
        (tester) async {
      await tester.pumpWidget(_wrap(
        ExerciseSlotRow(slot: _makeSlot(), onTap: () {}),
      ));
      expect(find.textContaining('PRESS'), findsOneWidget);
      expect(find.text('4 · 8–12'), findsOneWidget);
      expect(find.textContaining('PECHO'), findsOneWidget);
    });

    testWidgets('SCENARIO-089: renders ÚLTIMO badge and dash placeholder',
        (tester) async {
      await tester.pumpWidget(_wrap(
        ExerciseSlotRow(slot: _makeSlot(), onTap: () {}),
      ));
      expect(find.textContaining('ÚLTIMO'), findsOneWidget);
      expect(find.text('—'), findsAtLeastNWidgets(1));
    });

    testWidgets('SCENARIO-093: tap triggers onTap callback', (tester) async {
      var tapped = false;
      await tester.pumpWidget(_wrap(
        ExerciseSlotRow(
          slot: _makeSlot(),
          onTap: () => tapped = true,
        ),
      ));
      await tester.tap(find.byType(ExerciseSlotRow));
      expect(tapped, isTrue);
    });
  });
}
