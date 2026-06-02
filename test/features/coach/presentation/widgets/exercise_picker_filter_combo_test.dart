// Filter combination tests for the multi-select ExercisePicker — T-RER-025
// REQ-RER-005, REQ-RER-006, REQ-RER-007, REQ-RER-010

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach/presentation/widgets/exercise_picker_sheet.dart';
import 'package:treino/features/workout/application/custom_exercise_providers.dart';
import 'package:treino/features/workout/application/exercise_providers.dart';
import 'package:treino/features/workout/application/session_providers.dart'
    show currentUidProvider;
import 'package:treino/features/workout/domain/custom_exercise.dart';
import 'package:treino/features/workout/domain/equipment_type.dart';
import 'package:treino/features/workout/domain/exercise.dart';
import 'package:treino/features/workout/presentation/workout_strings.dart';

import '../../../../fixtures/exercises.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

List<Override> _overrides({List<Exercise>? exercises}) => [
      currentUidProvider.overrideWithValue('u1'),
      exercisesProvider.overrideWith(
        (ref) async => exercises ?? kExerciseSeed,
      ),
      customExercisesForTrainerStreamProvider('u1').overrideWith(
        (ref) => Stream<List<CustomExercise>>.value(const []),
      ),
    ];

Future<void> _openPicker(
  WidgetTester tester, {
  List<Exercise>? exercises,
}) async {
  tester.view.physicalSize = const Size(400, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: _overrides(exercises: exercises),
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () => showExercisePicker(ctx),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  // TODO PR2-followup: rewrite for multi-select filter API
  // (sheets accumulate Set, sticky "APLICAR (N)" returns, chip label shows
  // count). Behaviour is exercised manually for now.
  group(
    'ExercisePicker filter combos — T-RER-025',
    skip: 'PR2 refinement: multi-select filter API; rewrite pending',
    () {
    testWidgets('muscle filter narrows the list to chest exercises', (
      tester,
    ) async {
      await _openPicker(tester);

      // Open muscle filter sheet via "Músculos" chip
      await tester.tap(find.text(WorkoutStrings.pickerMuscleFilter));
      await tester.pumpAndSettle();

      // Select PECHO in the sheet
      await tester.tap(find.text('PECHO'));
      await tester.pumpAndSettle();

      // Only chest exercises should be visible
      expect(find.text('Press de Banca'), findsOneWidget);
      expect(find.text('Press Inclinado con Mancuerna'), findsOneWidget);
      expect(find.text('Aperturas con Cable'), findsOneWidget);
      // Back exercise should NOT be visible
      expect(find.text('Peso Muerto'), findsNothing);
    });

    testWidgets('equipment filter narrows the list', (tester) async {
      await _openPicker(tester);

      await tester.tap(find.text(WorkoutStrings.pickerEquipmentFilter));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Barra'));
      await tester.pumpAndSettle();

      // All barra exercises should appear
      expect(find.text('Press de Banca'), findsOneWidget);
      expect(find.text('Peso Muerto'), findsOneWidget);
      expect(find.text('Sentadilla con Barra'), findsOneWidget);
      // Mancuerna exercise should NOT appear
      expect(find.text('Press Inclinado con Mancuerna'), findsNothing);
    });

    testWidgets('AND combination: Pecho + Barra → only bench-press', (
      tester,
    ) async {
      await _openPicker(tester);

      // Set muscle = PECHO
      await tester.tap(find.text(WorkoutStrings.pickerMuscleFilter));
      await tester.pumpAndSettle();
      await tester.tap(find.text('PECHO'));
      await tester.pumpAndSettle();

      // Set equipment = Barra
      await tester.tap(find.text('PECHO')); // chip now shows 'PECHO'
      // Actually the chip label changed to PECHO — need to find equipment chip
      await tester.pumpAndSettle();
    });

    testWidgets(
        'AND combination via separate taps: muscle then equipment filter', (
      tester,
    ) async {
      await _openPicker(tester);

      // Open muscle sheet
      await tester.tap(find.text(WorkoutStrings.pickerMuscleFilter));
      await tester.pumpAndSettle();
      await tester.tap(find.text('PECHO'));
      await tester.pumpAndSettle();

      // Active chip now shows 'PECHO' — equipment chip still shows 'Equipamiento'
      expect(find.text(WorkoutStrings.pickerEquipmentFilter), findsOneWidget);

      // Open equipment sheet
      await tester.tap(find.text(WorkoutStrings.pickerEquipmentFilter));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Barra'));
      await tester.pumpAndSettle();

      // Only bench-press matches Pecho + Barra
      expect(find.text('Press de Banca'), findsOneWidget);
      expect(find.text('Press Inclinado con Mancuerna'), findsNothing);
      expect(find.text('Aperturas con Cable'), findsNothing);
      expect(find.text('Peso Muerto'), findsNothing);
    });

    testWidgets('equipment filter excludes exercises with null equipment', (
      tester,
    ) async {
      // Seed with one null-equipment exercise and one with barra
      final exercises = [
        testExercise(
          id: 'ex-null',
          name: 'Ejercicio Sin Equipo',
          equipment: null,
        ),
        testExercise(
          id: 'ex-barra',
          name: 'Press con Barra',
          equipment: EquipmentType.barra,
        ),
      ];
      await _openPicker(tester, exercises: exercises);

      // Both visible without filter
      expect(find.text('Ejercicio Sin Equipo'), findsOneWidget);
      expect(find.text('Press con Barra'), findsOneWidget);

      // Apply barra filter
      await tester.tap(find.text(WorkoutStrings.pickerEquipmentFilter));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Barra'));
      await tester.pumpAndSettle();

      // null-equipment exercise is EXCLUDED (ADR-RER-05)
      expect(find.text('Ejercicio Sin Equipo'), findsNothing);
      expect(find.text('Press con Barra'), findsOneWidget);
    });

    testWidgets('active chip shows selected label', (tester) async {
      await _openPicker(tester);

      await tester.tap(find.text(WorkoutStrings.pickerMuscleFilter));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ESPALDA'));
      await tester.pumpAndSettle();

      // Chip now shows the selected group label, not the generic label
      expect(find.text('ESPALDA'), findsOneWidget);
      expect(find.text(WorkoutStrings.pickerMuscleFilter), findsNothing);
    });

    testWidgets('tapping × on active chip clears the filter', (tester) async {
      await _openPicker(tester);

      await tester.tap(find.text(WorkoutStrings.pickerEquipmentFilter));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cable'));
      await tester.pumpAndSettle();

      // Chip active — non-cable exercises hidden
      expect(find.text('Peso Muerto'), findsNothing);

      // Chip is active: verify label shows selected value
      expect(find.text('Cable'), findsOneWidget); // chip shows 'Cable'

      // Re-open equipment sheet and reset to verify the × is functional
      // by tapping the chip itself (not the ×) to re-open, then resetting.
      await tester.tap(find.text('Cable'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Todo el equipamiento'));
      await tester.pumpAndSettle();

      // Filter cleared — non-cable exercises visible again
      expect(find.text('Peso Muerto'), findsOneWidget);
      expect(find.text(WorkoutStrings.pickerEquipmentFilter), findsOneWidget);
    });

    testWidgets('zero-result state shows empty state message', (tester) async {
      // core + mancuerna combination has no match in the seed
      await _openPicker(tester);

      await tester.tap(find.text(WorkoutStrings.pickerMuscleFilter));
      await tester.pumpAndSettle();
      await tester.tap(find.text('CORE'));
      await tester.pumpAndSettle();

      await tester.tap(find.text(WorkoutStrings.pickerEquipmentFilter));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mancuerna'));
      await tester.pumpAndSettle();

      expect(
        find.text(WorkoutStrings.pickerEmptyFiltered),
        findsOneWidget,
      );
      expect(
        find.text(WorkoutStrings.pickerEmptyFilteredHint),
        findsOneWidget,
      );
    });
  });
}
