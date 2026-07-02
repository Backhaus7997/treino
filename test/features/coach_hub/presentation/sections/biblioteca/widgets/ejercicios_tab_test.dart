// Widget tests for EjerciciosTab and ExerciseGridCard.
// REQ-BIBW-03, REQ-BIBW-04, REQ-BIBW-05, REQ-BIBW-06, REQ-BIBW-07,
// REQ-BIBW-11.
// SCENARIO-BIBW-03a, SCENARIO-BIBW-03b, SCENARIO-BIBW-07a, SCENARIO-BIBW-07b,
// SCENARIO-BIBW-11a.
// T-BIBW-003

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach_hub/presentation/sections/biblioteca/widgets/ejercicios_tab.dart';
import 'package:treino/features/workout/application/custom_exercise_providers.dart';
import 'package:treino/features/workout/application/exercise_providers.dart';
import 'package:treino/features/workout/application/session_providers.dart'
    show currentUidProvider;
import 'package:treino/features/workout/domain/custom_exercise.dart';
import 'package:treino/features/workout/domain/equipment_type.dart';
import 'package:treino/features/workout/domain/exercise.dart';

// ── Fixtures ──────────────────────────────────────────────────────────────────

const _kTrainerId = 'trainer-uid-widget-test';

const _bench = Exercise(
  id: 'bench-press',
  name: 'Press de Banca',
  muscleGroup: 'chest',
  category: 'compound',
  equipment: EquipmentType.barra,
  defaultRestSeconds: 90,
);

const _curl = Exercise(
  id: 'biceps-curl',
  name: 'Curl de Bíceps',
  muscleGroup: 'biceps',
  category: 'isolation',
);

final _customEx = CustomExercise(
  id: 'custom-squat',
  ownerId: _kTrainerId,
  name: 'Sentadilla Personalizada',
  muscleGroup: 'quads',
  createdAt: DateTime.utc(2026, 1, 1),
  updatedAt: DateTime.utc(2026, 1, 1),
);

// ── Helpers ───────────────────────────────────────────────────────────────────

Widget _wrap(
  Widget child, {
  List<Exercise> catalog = const [],
  List<CustomExercise> customs = const [],
  bool catalogLoading = false,
  bool catalogError = false,
}) {
  return ProviderScope(
    overrides: [
      currentUidProvider.overrideWithValue(_kTrainerId),
      exercisesProvider.overrideWith((ref) {
        // Loading: future que nunca completa (Completer) — se queda en
        // AsyncLoading SIN un Timer pendiente (un Future.delayed dispararía
        // el assert !timersPending en el teardown).
        if (catalogLoading) return Completer<List<Exercise>>().future;
        if (catalogError) {
          return Future<List<Exercise>>.error(Exception('catalog error'));
        }
        return Future<List<Exercise>>.value(catalog);
      }),
      customExercisesForTrainerStreamProvider(_kTrainerId).overrideWith(
        (ref) => Stream.value(customs),
      ),
    ],
    child: MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(body: child),
    ),
  );
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  // Force a desktop-like size so the grid renders properly.
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  group('EjerciciosTab — smoke renders', () {
    testWidgets('shows CircularProgressIndicator when AsyncLoading',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _wrap(const EjerciciosTab(), catalogLoading: true),
      );
      await tester.pump(); // single frame — catalog future still pending

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('shows error text when catalog AsyncError', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _wrap(const EjerciciosTab(), catalogError: true),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.textContaining('Error'), findsOneWidget);
    });

    testWidgets('renders grid cards when AsyncData', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _wrap(
          const EjerciciosTab(),
          catalog: const [_bench, _curl],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Press de Banca'), findsOneWidget);
      expect(find.text('Curl de Bíceps'), findsOneWidget);
    });

    testWidgets('shows empty-state when merged list is empty', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _wrap(const EjerciciosTab()), // no catalog, no customs
      );
      await tester.pumpAndSettle();

      // Should NOT show a grid, should show an empty-state cue
      expect(find.byType(GridView), findsNothing);
      expect(find.textContaining('ejercicio'), findsWidgets);
    });
  });

  group('EjerciciosTab — CUSTOM badge', () {
    testWidgets(
        'CUSTOM badge present on custom exercise card — SCENARIO-BIBW-03a',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _wrap(
          const EjerciciosTab(),
          catalog: const [_bench],
          customs: [_customEx],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('CUSTOM'), findsOneWidget);
    });

    testWidgets('No CUSTOM badge on catalog exercise card', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _wrap(
          const EjerciciosTab(),
          catalog: const [_bench],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('CUSTOM'), findsNothing);
    });
  });

  group('EjerciciosTab — exercise detail dialog', () {
    testWidgets('tap exercise card opens AlertDialog — SCENARIO-BIBW-07a',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _wrap(
          const EjerciciosTab(),
          catalog: const [_bench],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Press de Banca'));
      await tester.pumpAndSettle();

      // AlertDialog should be present
      expect(find.byType(AlertDialog), findsOneWidget);
      // No BottomSheet
      expect(find.byType(BottomSheet), findsNothing);
    });

    testWidgets('dialog has Cerrar action button — SCENARIO-BIBW-07b',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _wrap(
          const EjerciciosTab(),
          catalog: const [_bench],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Press de Banca'));
      await tester.pumpAndSettle();

      expect(find.text('Cerrar'), findsOneWidget);

      // Dismiss dialog
      await tester.tap(find.text('Cerrar'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
    });
  });
}
