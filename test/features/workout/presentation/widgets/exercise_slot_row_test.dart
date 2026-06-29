import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/workout/domain/routine_slot.dart';
import 'package:treino/features/workout/presentation/widgets/exercise_slot_row.dart';
import 'package:treino/l10n/app_l10n.dart';

Widget _wrap(Widget w) => MaterialApp(
      theme: AppTheme.dark(),
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      locale: const Locale('es'),
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
  String? notes,
}) =>
    RoutineSlot(
      exerciseId: exerciseId,
      exerciseName: exerciseName,
      muscleGroup: muscleGroup,
      targetSets: targetSets,
      targetRepsMin: targetRepsMin,
      targetRepsMax: targetRepsMax,
      restSeconds: restSeconds,
      notes: notes,
    );

void main() {
  group('ExerciseSlotRow', () {
    testWidgets(
        'SCENARIO-088: renders exercise name, sets·reps, and muscle group',
        (tester) async {
      await tester.pumpWidget(_wrap(
        ExerciseSlotRow(slot: _makeSlot(), index: 1, onTap: () {}),
      ));
      expect(find.textContaining('PRESS'), findsOneWidget);
      expect(find.text('4 · 8–12'), findsOneWidget);
      expect(find.textContaining('PECHO'), findsOneWidget);
    });

    testWidgets('SCENARIO-089: renders ÚLTIMO badge and dash placeholder',
        (tester) async {
      await tester.pumpWidget(_wrap(
        ExerciseSlotRow(slot: _makeSlot(), index: 1, onTap: () {}),
      ));
      expect(find.textContaining('ÚLTIMO'), findsOneWidget);
      expect(find.text('—'), findsAtLeastNWidgets(1));
    });

    testWidgets('SCENARIO-093: tap triggers onTap callback', (tester) async {
      var tapped = false;
      await tester.pumpWidget(_wrap(
        ExerciseSlotRow(
          slot: _makeSlot(),
          index: 1,
          onTap: () => tapped = true,
        ),
      ));
      await tester.tap(find.byType(ExerciseSlotRow));
      expect(tapped, isTrue);
    });

    testWidgets('index renders as 1-based ordinal in leading box',
        (tester) async {
      await tester.pumpWidget(_wrap(
        ExerciseSlotRow(slot: _makeSlot(), index: 3, onTap: () {}),
      ));
      expect(find.text('3'), findsOneWidget);
    });

    testWidgets(
        'SCENARIO-815: shows the coach note + "DEL COACH" tag when the slot '
        'has notes', (tester) async {
      await tester.pumpWidget(_wrap(
        ExerciseSlotRow(
          slot: _makeSlot(notes: 'Bajá 3 seg la excéntrica'),
          index: 1,
          onTap: () {},
        ),
      ));
      expect(find.text('Bajá 3 seg la excéntrica'), findsOneWidget);
      expect(find.text('DEL COACH'), findsOneWidget);
    });

    testWidgets(
        'SCENARIO-818: renders no note when slot.notes is null (legacy slot)',
        (tester) async {
      await tester.pumpWidget(_wrap(
        ExerciseSlotRow(slot: _makeSlot(), index: 1, onTap: () {}),
      ));
      expect(find.text('DEL COACH'), findsNothing);
    });

    testWidgets('SCENARIO-819: renders no note when slot.notes is blank',
        (tester) async {
      await tester.pumpWidget(_wrap(
        ExerciseSlotRow(slot: _makeSlot(notes: '   '), index: 1, onTap: () {}),
      ));
      expect(find.text('DEL COACH'), findsNothing);
    });
  });
}
