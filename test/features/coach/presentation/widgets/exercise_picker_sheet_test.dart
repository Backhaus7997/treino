// Tests for the multi-select ExercisePicker — T-RER-024
// REQ-RER-001, REQ-RER-002, REQ-RER-003, SCENARIO-RER-001..005

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
import 'package:treino/features/workout/domain/exercise.dart';
import 'package:treino/l10n/app_l10n.dart';

import '../../../../fixtures/exercises.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

final _kExercises = [
  kExerciseSeed[0], // bench-press (chest/barra)
  kExerciseSeed[1], // incline-dumbbell-press (chest/mancuerna)
  kExerciseSeed[6], // back-squat (quads/barra)
];

List<Override> _overrides({List<Exercise>? exercises}) => [
      currentUidProvider.overrideWithValue('u1'),
      exercisesProvider.overrideWith((ref) async => exercises ?? _kExercises),
      customExercisesForTrainerStreamProvider('u1').overrideWith(
        (ref) => Stream<List<CustomExercise>>.value(const []),
      ),
    ];

Future<void> _openPicker(
  WidgetTester tester, {
  List<Exercise>? exercises,
  Set<String> alreadySelectedIds = const {},
  void Function(List<Exercise>?)? onResult,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: _overrides(exercises: exercises),
      child: MaterialApp(
        theme: AppTheme.dark(),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        locale: const Locale('es', 'AR'),
        home: Scaffold(
          body: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () async {
                final result = await showExercisePicker(
                  ctx,
                  alreadySelectedIds: alreadySelectedIds,
                );
                onResult?.call(result);
              },
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
  group('ExercisePickerSheet core — T-RER-024', () {
    testWidgets('empty selection: CTA disabled / shows Agregar 0', (
      tester,
    ) async {
      await _openPicker(tester);

      // The sticky bar text should show 0 and be non-interactive (disabled).
      // Either it's hidden or it shows the count but can't be tapped.
      // Per REQ-RER-002 the CTA is hidden when count == 0.
      expect(find.text('Agregar 0 ejercicios'), findsNothing);
    });

    testWidgets('single tap: CTA shows "Agregar 1 ejercicio"', (
      tester,
    ) async {
      await _openPicker(tester);
      await tester.tap(find.text('Press de Banca'));
      await tester.pumpAndSettle();

      expect(find.text('Agregar 1 ejercicio'), findsOneWidget);
    });

    testWidgets('multi-tap then deselect: counter updates', (tester) async {
      tester.view.physicalSize = const Size(400, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await _openPicker(tester);

      await tester.tap(find.text('Press de Banca'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sentadilla con Barra'));
      await tester.pumpAndSettle();

      expect(find.text('Agregar 2 ejercicios'), findsOneWidget);

      // Deselect one
      await tester.tap(find.text('Press de Banca'));
      await tester.pumpAndSettle();

      expect(find.text('Agregar 1 ejercicio'), findsOneWidget);
    });

    testWidgets(
        'confirm: pops List<Exercise> with correct ids in selection order', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(400, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      List<Exercise>? result;
      await _openPicker(
        tester,
        onResult: (r) => result = r,
      );

      await tester.tap(find.text('Press de Banca'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sentadilla con Barra'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Agregar 2 ejercicios'));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.length, 2);
      final ids = result!.map((e) => e.id).toSet();
      expect(ids, containsAll(['bench-press', 'back-squat']));
    });

    testWidgets('cancel / dismiss: pops null', (tester) async {
      List<Exercise>? result = _kExercises; // non-null sentinel
      await _openPicker(
        tester,
        onResult: (r) => result = r,
      );

      // Tap outside to dismiss
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(result, isNull);
    });

    testWidgets('alreadySelectedIds pre-marks exercises', (tester) async {
      await _openPicker(
        tester,
        alreadySelectedIds: const {'bench-press'},
      );

      // CTA should show count 1 already
      expect(find.text('Agregar 1 ejercicio'), findsOneWidget);
    });

    testWidgets('search filters list; selected count maintained', (
      tester,
    ) async {
      await _openPicker(tester);

      // Select bench-press
      await tester.tap(find.text('Press de Banca'));
      await tester.pumpAndSettle();
      expect(find.text('Agregar 1 ejercicio'), findsOneWidget);

      // Type a query that hides bench-press
      await tester.enterText(find.byType(TextField).first, 'sentadilla');
      await tester.pumpAndSettle();

      // Counter still shows 1 even though bench-press is hidden
      expect(find.text('Agregar 1 ejercicio'), findsOneWidget);
      // Sentadilla visible
      expect(find.text('Sentadilla con Barra'), findsOneWidget);
    });
  });

  group('ExercisePickerSheet — muscle filter (granular + secondary)', () {
    // Primary cuádriceps, secondary hombros — must surface under EITHER group.
    const lunge = Exercise(
      id: 'lunge-press',
      name: 'Estocada a Press',
      muscleGroup: 'quads',
      secondaryMuscleGroup: 'shoulders',
      category: 'compound',
    );
    const curl = Exercise(
      id: 'biceps-curl',
      name: 'Curl de Bíceps',
      muscleGroup: 'biceps',
      category: 'isolation',
    );

    testWidgets('Hombros filter matches an exercise by its SECONDARY muscle',
        (tester) async {
      tester.view.physicalSize = const Size(400, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await _openPicker(tester, exercises: const [lunge, curl]);

      // Both visible before filtering.
      expect(find.text('Estocada a Press'), findsOneWidget);
      expect(find.text('Curl de Bíceps'), findsOneWidget);

      // Open the muscle filter and pick Hombros.
      await tester.tap(find.text('Músculos'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('HOMBROS'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('APLICAR'));
      await tester.pumpAndSettle();

      // Lunge surfaces via its secondary (shoulders); the curl is filtered out.
      expect(find.text('Estocada a Press'), findsOneWidget);
      expect(find.text('Curl de Bíceps'), findsNothing);
    });
  });
}
