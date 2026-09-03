// Issue #640 — PR#1: "Copiar sets del anterior" en el menú del slot.
//
// Cubre:
//   - copyPrescriptionInto: copia profunda de la semana visible, arrastra el
//     modo de medición, NO toca la presencia semanal (ADR-WPRES) ni las otras
//     semanas (mismo criterio que "Duplicar semana", REQ-PERIOD-014).
//   - modo rango (MÍN/MÁX), modo duración (TIEMPO) y SetType W/D/F sobreviven.
//   - UI: el ítem del menú está deshabilitado en el primer ejercicio del día y
//     copia (previa confirmación) en los siguientes.
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

// ── Record helpers for the bridge ─────────────────────────────────────────────

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

/// Adds two chest exercises to Día 1 in a single picker session.
Future<void> _addTwoExercises(WidgetTester tester) async {
  await desplazarHastaAgregarEjercicio(tester);
  await desplazarHastaAgregarEjercicio(tester);
  await tester.tap(find.text('Agregar ejercicio'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Press de Banca').first);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Press Inclinado con Mancuerna').first);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Agregar 2 ejercicios'));
  await tester.pumpAndSettle();
  // Desde este cambio el ejercicio agregado nace PLEGADO: quien avisa
  // que le falta completar sets es el borde rojo, no la card abierta.
  await expandirEjercicios(tester);
}

/// Set-row inputs are the only fields carrying these hints, so the hint is a
/// stable way to address "the KG field of the Nth slot" without private types.
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

Future<void> _openSlotMenu(WidgetTester tester, int slotIndex) async {
  final finder = find.byKey(Key('slot_menu_button_$slotIndex'));
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  // ── Unit: copyPrescriptionInto ─────────────────────────────────────────────

  group('copyPrescriptionInto — semana visible', () {
    test('copia los sets de la semana indicada y deja las otras intactas', () {
      final target = RoutineEditorTestBridge.copyPrescriptionBridge(
        sourceMode: ExerciseMode.reps,
        sourceRepMode: RepMode.single,
        sourceWeeklySets: [
          [_set(weightKg: 60, reps: 10)],
          [_set(weightKg: 80, reps: 6)],
        ],
        targetMode: ExerciseMode.reps,
        targetRepMode: RepMode.single,
        targetWeeklySets: [
          [_set(weightKg: 20, reps: 15)],
          [_set(weightKg: 25, reps: 12)],
        ],
        week: 1,
      );

      // Semana 0 (no copiada) queda como estaba.
      expect(target.weeklySets[0].first.weightKg, closeTo(20, 0.001));
      expect(target.weeklySets[0].first.reps, 15);
      // Semana 1 (copiada) toma los valores del source.
      expect(target.weeklySets[1].first.weightKg, closeTo(80, 0.001));
      expect(target.weeklySets[1].first.reps, 6);
    });

    test('reemplaza la lista entera: 3 sets del source pisan 1 del target', () {
      final target = RoutineEditorTestBridge.copyPrescriptionBridge(
        sourceMode: ExerciseMode.reps,
        sourceRepMode: RepMode.single,
        sourceWeeklySets: [
          [
            _set(weightKg: 60, reps: 10),
            _set(weightKg: 60, reps: 10),
            _set(weightKg: 60, reps: 8),
          ],
        ],
        targetMode: ExerciseMode.reps,
        targetRepMode: RepMode.single,
        targetWeeklySets: [
          [_set(weightKg: 20, reps: 15)],
        ],
        week: 0,
      );

      expect(target.weeklySets[0].length, 3);
      expect(
        target.weeklySets[0].map((s) => s.reps).toList(),
        [10, 10, 8],
      );
    });

    test('es copia profunda: mutar el source después no toca el target', () {
      final target = RoutineEditorTestBridge.copyPrescriptionBridge(
        sourceMode: ExerciseMode.reps,
        sourceRepMode: RepMode.single,
        sourceWeeklySets: [
          [_set(weightKg: 60, reps: 10)],
        ],
        targetMode: ExerciseMode.reps,
        targetRepMode: RepMode.single,
        targetWeeklySets: [
          [_set()],
        ],
        week: 0,
        mutateSourceAfterCopy: true,
      );

      expect(target.weeklySets[0].first.reps, 10);
      expect(target.weeklySets[0].first.weightKg, closeTo(60, 0.001));
      expect(target.weeklySets[0].first.type, SetType.normal);
    });

    test('índice de semana fuera de rango → no hace nada', () {
      final target = RoutineEditorTestBridge.copyPrescriptionBridge(
        sourceMode: ExerciseMode.duration,
        sourceRepMode: RepMode.single,
        sourceWeeklySets: [
          [_set(durationSeconds: 45)],
        ],
        targetMode: ExerciseMode.reps,
        targetRepMode: RepMode.single,
        targetWeeklySets: [
          [_set(weightKg: 20, reps: 15)],
        ],
        week: 3,
      );

      expect(target.exerciseMode, ExerciseMode.reps,
          reason: 'un índice inválido no debe re-modear el slot');
      expect(target.weeklySets[0].first.reps, 15);
    });
  });

  // ── Unit: modos de medición ────────────────────────────────────────────────

  group('copyPrescriptionInto — modos', () {
    test('modo duración: arrastra TIEMPO y el exerciseMode del source', () {
      final target = RoutineEditorTestBridge.copyPrescriptionBridge(
        sourceMode: ExerciseMode.duration,
        sourceRepMode: RepMode.single,
        sourceWeeklySets: [
          [_set(durationSeconds: 45), _set(durationSeconds: 30)],
        ],
        targetMode: ExerciseMode.reps,
        targetRepMode: RepMode.single,
        targetWeeklySets: [
          [_set(weightKg: 20, reps: 15)],
        ],
        week: 0,
      );

      expect(target.exerciseMode, ExerciseMode.duration);
      expect(
        target.weeklySets[0].map((s) => s.durationSeconds).toList(),
        [45, 30],
      );
    });

    test('modo rango: arrastra repMode + MÍN/MÁX', () {
      final target = RoutineEditorTestBridge.copyPrescriptionBridge(
        sourceMode: ExerciseMode.reps,
        sourceRepMode: RepMode.range,
        sourceWeeklySets: [
          [_set(weightKg: 40, repsMin: 8, repsMax: 12)],
        ],
        targetMode: ExerciseMode.reps,
        targetRepMode: RepMode.single,
        targetWeeklySets: [
          [_set(weightKg: 20, reps: 15)],
        ],
        week: 0,
      );

      expect(target.repMode, RepMode.range);
      expect(target.weeklySets[0].first.repsMin, 8);
      expect(target.weeklySets[0].first.repsMax, 12);
    });

    test('los sets copiados quedan válidos para el modo copiado', () {
      final target = RoutineEditorTestBridge.copyPrescriptionBridge(
        sourceMode: ExerciseMode.duration,
        sourceRepMode: RepMode.single,
        sourceWeeklySets: [
          [_set(durationSeconds: 60)],
        ],
        targetMode: ExerciseMode.reps,
        targetRepMode: RepMode.single,
        targetWeeklySets: [
          [_set(weightKg: 20, reps: 15)],
        ],
        week: 0,
      );

      // Sin arrastrar el modo, este set quedaría con duración pero renderizado
      // como REPS → inválido y con borde rojo. Ese era el riesgo del issue.
      expect(
        RoutineEditorTestBridge.isSetValidBridge(
          exerciseMode: target.exerciseMode,
          repMode: target.repMode,
          durationSeconds: target.weeklySets[0].first.durationSeconds,
        ),
        isTrue,
      );
    });
  });

  // ── Unit: SetType y presencia ──────────────────────────────────────────────

  group('copyPrescriptionInto — SetType y presencia', () {
    test('W / D / F sobreviven la copia (usa copy(), no clone())', () {
      final target = RoutineEditorTestBridge.copyPrescriptionBridge(
        sourceMode: ExerciseMode.reps,
        sourceRepMode: RepMode.single,
        sourceWeeklySets: [
          [
            _set(type: SetType.warmup, weightKg: 20, reps: 15),
            _set(reps: 10),
            _set(type: SetType.drop, weightKg: 40, reps: 12),
            _set(type: SetType.failure),
          ],
        ],
        targetMode: ExerciseMode.reps,
        targetRepMode: RepMode.single,
        targetWeeklySets: [
          [_set(reps: 5)],
        ],
        week: 0,
      );

      expect(
        target.weeklySets[0].map((s) => s.type).toList(),
        [SetType.warmup, SetType.normal, SetType.drop, SetType.failure],
      );
    });

    test('la máscara de presencia del target queda intacta (ADR-WPRES)', () {
      final target = RoutineEditorTestBridge.copyPrescriptionBridge(
        sourceMode: ExerciseMode.reps,
        sourceRepMode: RepMode.single,
        sourceWeeklySets: [
          [_set(reps: 10)],
          [_set(reps: 10)],
        ],
        targetMode: ExerciseMode.reps,
        targetRepMode: RepMode.single,
        targetWeeklySets: [
          [_set()],
          [_set()],
        ],
        week: 1,
        targetActiveWeeks: {1},
      );

      expect(target.activeWeeks, [1],
          reason: 'copiar prescripción no agrega ni saca semanas');
    });
  });

  // ── Widget: menú del slot ──────────────────────────────────────────────────

  group('menú del slot — Copiar sets del anterior', () {
    testWidgets('el primer ejercicio del día lo tiene deshabilitado',
        (tester) async {
      await _pumpEditor(tester);
      await _addTwoExercises(tester);

      await _openSlotMenu(tester, 0);
      expect(find.text('Copiar sets del anterior'), findsOneWidget);

      // Deshabilitado: tocarlo no abre la confirmación.
      await tester.tap(find.text('Copiar sets del anterior'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('copy_prescription_confirm_button')),
        findsNothing,
      );
    });

    testWidgets('copia KG y REPS del ejercicio anterior tras confirmar',
        (tester) async {
      await _pumpEditor(tester);
      await _addTwoExercises(tester);

      await _enterInField(tester, _fieldsWithHint('kg').at(0), '100');
      await _enterInField(tester, _fieldsWithHint('reps').at(0), '8');

      expect(find.text('100'), findsOneWidget);
      expect(find.text('8'), findsOneWidget);

      await _openSlotMenu(tester, 1);
      await tester.tap(find.text('Copiar sets del anterior'));
      await tester.pumpAndSettle();

      expect(find.text('¿Copiar sets?'), findsOneWidget);
      await tester
          .tap(find.byKey(const Key('copy_prescription_confirm_button')));
      await tester.pumpAndSettle();

      // Ahora los dos ejercicios muestran la misma prescripción.
      expect(find.text('100'), findsNWidgets(2));
      expect(find.text('8'), findsNWidgets(2));
    });

    testWidgets('cancelar deja el ejercicio destino como estaba',
        (tester) async {
      await _pumpEditor(tester);
      await _addTwoExercises(tester);

      await _enterInField(tester, _fieldsWithHint('kg').at(0), '100');
      await _enterInField(tester, _fieldsWithHint('reps').at(0), '8');

      await _openSlotMenu(tester, 1);
      await tester.tap(find.text('Copiar sets del anterior'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();

      expect(find.text('100'), findsOneWidget);
      expect(find.text('8'), findsOneWidget);
    });
  });
}
