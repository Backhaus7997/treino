// Issue #640 — rellenar la columna KG. Gesto actualizado por #867.
//
// El bulk-fill vivía en el header de KG, el único sin gesto. Era un tap sobre
// un label de 10,5 px con un ícono de 11: existía, y no lo encontraba nadie.
// Desde #867 es "A TODAS" en la barra sobre el teclado, con un target de 44.
//
// Con el disparador cambió la FUENTE: antes replicaba siempre desde el primer
// set —el header no pertenece a ninguna fila—, ahora desde la celda que se está
// editando. Replicar el primer set mientras el usuario mira el tercero sería
// replicar un número que no tiene delante.
//
// Cubre:
//   - applyColumnWeights mueve SOLO el peso: SetType, reps, rango y duración
//     sobreviven intactos.
//   - la afordancia no aparece en modo duración ni con un único set.
//   - primer set sin peso → avisa en vez de vaciar la columna en silencio.
//   - deshacer restaura los valores previos exactos.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/analytics/analytics_service.dart';
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
import 'package:treino/features/workout/domain/set_enums.dart';
import 'package:treino/features/workout/presentation/routine_editor_mode.dart';
import 'package:treino/features/workout/presentation/routine_editor_screen.dart';
import 'package:treino/l10n/app_l10n.dart';

import '../../../fixtures/exercises.dart';
import '../../../helpers/fake_analytics_service.dart';
import '../../../fixtures/routine_editor_ui.dart';

// ── Mocks ─────────────────────────────────────────────────────────────────────

class _MockRoutineRepository extends Mock implements RoutineRepository {}

// ── Record helper for the bridge ──────────────────────────────────────────────

typedef _SetRecord = ({
  SetType type,
  double? weightKg,
  int? reps,
  int? repsMin,
  int? repsMax,
  int? durationSeconds,
});

_SetRecord _set({
  SetType type = SetType.normal,
  double? weightKg,
  int? reps,
  int? repsMin,
  int? repsMax,
  int? durationSeconds,
}) =>
    (
      type: type,
      weightKg: weightKg,
      reps: reps,
      repsMin: repsMin,
      repsMax: repsMax,
      durationSeconds: durationSeconds,
    );

// ── Widget harness ────────────────────────────────────────────────────────────

Future<void> _pumpEditor(WidgetTester tester) async {
  const uid = 'user-1';
  final router = GoRouter(
    initialLocation: '/workout/editor',
    routes: [
      GoRoute(
        path: '/workout/editor',
        pageBuilder: (context, state) => const NoTransitionPage(
          child: RoutineEditorScreen(mode: SelfCreating()),
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
      overrides: [
        currentUidProvider.overrideWithValue(uid),
        routineRepositoryProvider.overrideWithValue(_MockRoutineRepository()),
        exercisesProvider.overrideWith((ref) async => kExerciseSeed),
        customExercisesForTrainerStreamProvider(uid).overrideWith(
          (ref) => Stream<List<CustomExercise>>.value(const <CustomExercise>[]),
        ),
        analyticsServiceProvider.overrideWithValue(FakeAnalyticsService()),
        userCreatedRoutinesProvider(uid).overrideWith(
          (ref) => Stream.value(const []),
        ),
      ],
      child: MaterialApp.router(
        theme: AppTheme.dark(),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        locale: const Locale('es', 'AR'),
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _addBenchPress(WidgetTester tester) async {
  await desplazarHastaAgregarEjercicio(tester);
  await desplazarHastaAgregarEjercicio(tester);
  await tester.tap(find.text('Agregar ejercicio'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Press de Banca').first);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Agregar 1 ejercicio'));
  await tester.pumpAndSettle();
}

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _addSet(WidgetTester tester) =>
    _tapVisible(tester, find.byKey(const Key('add_set_button')));

/// Set-row inputs are the only fields carrying these hints.
Finder _fieldsWithHint(String hint) => find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.hintText == hint,
    );

Future<void> _enterInField(
  WidgetTester tester,
  Finder finder,
  String value,
) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.enterText(finder, value);
  await tester.pumpAndSettle();
}

Finder get _fillButton => find.byKey(const Key('accessory_fill_column'));

/// Enfoca la celda KG número [i], con el teclado simulado, de modo que la
/// barra de accesorio quede en el árbol.
Future<void> _enfocarKg(WidgetTester tester, int i) =>
    enfocarCelda(tester, _fieldsWithHint('kg').at(i));

/// Lets the SnackBar's auto-dismiss timer run out so the test ends clean.
Future<void> _flushSnackBar(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 6));
  await tester.pumpAndSettle();
}

void main() {
  // ── Unit: applyColumnWeights ───────────────────────────────────────────────

  group('applyColumnWeights — mueve solo el peso', () {
    test('aplica el peso a toda la columna', () {
      final slot = RoutineEditorTestBridge.fillColumnWeightsBridge(
        exerciseMode: ExerciseMode.reps,
        repMode: RepMode.single,
        sets: [
          _set(weightKg: 100, reps: 8),
          _set(reps: 8),
          _set(reps: 6),
        ],
        weights: const [100, 100, 100],
      );

      expect(
        slot.sets.map((s) => s.weightKg).toList(),
        [closeTo(100, 0.001), closeTo(100, 0.001), closeTo(100, 0.001)],
      );
    });

    test('las reps quedan intactas', () {
      final slot = RoutineEditorTestBridge.fillColumnWeightsBridge(
        exerciseMode: ExerciseMode.reps,
        repMode: RepMode.single,
        sets: [
          _set(weightKg: 100, reps: 12),
          _set(reps: 10),
          _set(reps: 8),
        ],
        weights: const [100, 100, 100],
      );

      expect(slot.sets.map((s) => s.reps).toList(), [12, 10, 8]);
    });

    test('W / D / F conservan su tipo', () {
      final slot = RoutineEditorTestBridge.fillColumnWeightsBridge(
        exerciseMode: ExerciseMode.reps,
        repMode: RepMode.single,
        sets: [
          _set(type: SetType.warmup, weightKg: 40, reps: 15),
          _set(reps: 10),
          _set(type: SetType.drop, reps: 12),
          _set(type: SetType.failure),
        ],
        weights: const [40, 40, 40, 40],
      );

      expect(
        slot.sets.map((s) => s.type).toList(),
        [SetType.warmup, SetType.normal, SetType.drop, SetType.failure],
      );
    });

    test('modo rango: MÍN/MÁX quedan intactos', () {
      final slot = RoutineEditorTestBridge.fillColumnWeightsBridge(
        exerciseMode: ExerciseMode.reps,
        repMode: RepMode.range,
        sets: [
          _set(weightKg: 50, repsMin: 8, repsMax: 12),
          _set(repsMin: 6, repsMax: 10),
        ],
        weights: const [50, 50],
      );

      expect(slot.sets.map((s) => s.repsMin).toList(), [8, 6]);
      expect(slot.sets.map((s) => s.repsMax).toList(), [12, 10]);
    });

    test('modo duración: TIEMPO queda intacto', () {
      final slot = RoutineEditorTestBridge.fillColumnWeightsBridge(
        exerciseMode: ExerciseMode.duration,
        repMode: RepMode.single,
        sets: [
          _set(weightKg: 10, durationSeconds: 45),
          _set(durationSeconds: 30),
        ],
        weights: const [10, 10],
      );

      expect(slot.sets.map((s) => s.durationSeconds).toList(), [45, 30]);
    });

    test('deshacer restaura los valores previos, nulls incluidos', () {
      final slot = RoutineEditorTestBridge.fillColumnWeightsBridge(
        exerciseMode: ExerciseMode.reps,
        repMode: RepMode.single,
        sets: [
          _set(weightKg: 100, reps: 8),
          _set(weightKg: 100, reps: 8),
          _set(weightKg: 100, reps: 8),
        ],
        weights: const [100, 60, null],
      );

      expect(slot.sets[0].weightKg, closeTo(100, 0.001));
      expect(slot.sets[1].weightKg, closeTo(60, 0.001));
      expect(slot.sets[2].weightKg, isNull);
    });

    test('una lista de pesos más corta deja el resto sin tocar', () {
      final slot = RoutineEditorTestBridge.fillColumnWeightsBridge(
        exerciseMode: ExerciseMode.reps,
        repMode: RepMode.single,
        sets: [
          _set(weightKg: 100, reps: 8),
          _set(weightKg: 20, reps: 8),
        ],
        weights: const [50],
      );

      expect(slot.sets[0].weightKg, closeTo(50, 0.001));
      expect(slot.sets[1].weightKg, closeTo(20, 0.001));
    });
  });

  // ── Widget: afordancia en el header ────────────────────────────────────────

  group('barra de accesorio — visibilidad de "A TODAS"', () {
    testWidgets('no aparece con un solo set', (tester) async {
      usarViewportAlto(tester);
      await _pumpEditor(tester);
      await _addBenchPress(tester);
      await _enfocarKg(tester, 0);

      expect(_fillButton, findsNothing,
          reason: 'con un set único no hay dónde replicar');
    });

    testWidgets('aparece a partir del segundo set', (tester) async {
      usarViewportAlto(tester);
      await _pumpEditor(tester);
      await _addBenchPress(tester);
      await _addSet(tester);
      await _enfocarKg(tester, 0);

      expect(_fillButton, findsOneWidget);
    });

    testWidgets('sin una celda en edición no hay barra', (tester) async {
      usarViewportAlto(tester);
      await _pumpEditor(tester);
      await _addBenchPress(tester);
      await _addSet(tester);

      expect(_fillButton, findsNothing,
          reason: 'la barra es un accesorio del teclado: sin celda enfocada '
              'no tiene sobre qué actuar');
    });

    testWidgets('no aparece en modo duración (no hay columna KG)',
        (tester) async {
      usarViewportAlto(tester);
      await _pumpEditor(tester);
      await _addBenchPress(tester);
      await _addSet(tester);
      await _enfocarKg(tester, 0);
      expect(_fillButton, findsOneWidget);

      // El header de REPS conserva su gesto original: abre el picker de modo.
      await _tapVisible(tester, find.text('REPS'));
      await _tapVisible(tester, find.text('Tiempo').last);

      expect(find.text('TIEMPO'), findsOneWidget);
      expect(_fillButton, findsNothing);
    });
  });

  // ── Widget: rellenar y deshacer ────────────────────────────────────────────

  group('barra de accesorio — rellenar la columna', () {
    testWidgets('replica el peso de la celda enfocada en todos',
        (tester) async {
      usarViewportAlto(tester);
      await _pumpEditor(tester);
      await _addBenchPress(tester);
      await _addSet(tester);
      await _addSet(tester);

      await _enterInField(tester, _fieldsWithHint('kg').at(0), '100');
      await _enterInField(tester, _fieldsWithHint('reps').at(0), '8');
      await _enterInField(tester, _fieldsWithHint('reps').at(1), '10');
      await _enterInField(tester, _fieldsWithHint('reps').at(2), '12');

      expect(find.text('100'), findsOneWidget);

      await _enfocarKg(tester, 0);
      await _tapVisible(tester, _fillButton);

      expect(find.text('100'), findsNWidgets(3));
      // Las reps por fila no se tocan.
      expect(find.text('8'), findsOneWidget);
      expect(find.text('10'), findsOneWidget);
      expect(find.text('12'), findsOneWidget);

      await _flushSnackBar(tester);
    });

    testWidgets('la fuente es la celda en edición, no siempre la primera',
        (tester) async {
      // Es el cambio de semántica que trajo #867: el disparador ya no es un
      // header sin fila, es la celda que el usuario está mirando.
      usarViewportAlto(tester);
      await _pumpEditor(tester);
      await _addBenchPress(tester);
      await _addSet(tester);

      await _enterInField(tester, _fieldsWithHint('kg').at(0), '100');
      await _enterInField(tester, _fieldsWithHint('kg').at(1), '60');
      await _enterInField(tester, _fieldsWithHint('reps').at(0), '8');
      await _enterInField(tester, _fieldsWithHint('reps').at(1), '8');

      await _enfocarKg(tester, 1);
      await _tapVisible(tester, _fillButton);

      expect(find.text('60'), findsNWidgets(2),
          reason: 'replicó el 60 de la SEGUNDA fila, que era la enfocada');
      expect(find.text('100'), findsNothing);

      await _flushSnackBar(tester);
    });

    testWidgets('deshacer devuelve la columna a como estaba', (tester) async {
      usarViewportAlto(tester);
      await _pumpEditor(tester);
      await _addBenchPress(tester);
      await _addSet(tester);

      await _enterInField(tester, _fieldsWithHint('kg').at(0), '100');
      await _enterInField(tester, _fieldsWithHint('kg').at(1), '60');
      await _enterInField(tester, _fieldsWithHint('reps').at(0), '8');
      await _enterInField(tester, _fieldsWithHint('reps').at(1), '8');

      await _enfocarKg(tester, 0);
      await _tapVisible(tester, _fillButton);
      expect(find.text('100'), findsNWidgets(2));
      expect(find.text('60'), findsNothing);

      await tester.tap(find.byKey(const Key('fill_kg_undo_action')));
      await tester.pumpAndSettle();

      expect(find.text('100'), findsOneWidget);
      expect(find.text('60'), findsOneWidget);

      await _flushSnackBar(tester);
    });

    testWidgets('con la celda fuente vacía avisa y no vacía la columna',
        (tester) async {
      usarViewportAlto(tester);
      await _pumpEditor(tester);
      await _addBenchPress(tester);
      await _addSet(tester);

      // Solo el SEGUNDO set tiene peso; se enfoca el PRIMERO, que está vacío.
      await _enterInField(tester, _fieldsWithHint('kg').at(1), '60');
      await _enterInField(tester, _fieldsWithHint('reps').at(0), '8');
      await _enterInField(tester, _fieldsWithHint('reps').at(1), '8');

      await _enfocarKg(tester, 0);
      await _tapVisible(tester, _fillButton);

      expect(
        find.text('Cargá el peso de este set para poder replicarlo.'),
        findsOneWidget,
        reason: 'dice "este set" y no "el primer set": la fuente es la celda '
            'enfocada, y mandar al usuario a la primera fila lo dejaba '
            'corrigiendo un valor que no se va a replicar',
      );
      expect(find.text('60'), findsOneWidget,
          reason: 'el peso ya cargado no se pisa con un vacío');

      await _flushSnackBar(tester);
    });
  });
}
