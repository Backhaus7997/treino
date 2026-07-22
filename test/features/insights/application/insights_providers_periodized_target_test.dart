import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/features/insights/application/insights_providers.dart';
import 'package:treino/features/insights/domain/muscle_group.dart';
import 'package:treino/features/workout/application/exercise_providers.dart';
import 'package:treino/features/workout/application/routine_providers.dart';
import 'package:treino/features/workout/application/session_providers.dart';
import 'package:treino/features/workout/data/session_repository.dart';
import 'package:treino/features/workout/domain/exercise.dart';
import 'package:treino/features/workout/domain/routine.dart';
import 'package:treino/features/workout/domain/session_status.dart';

import '../../workout/application/stub_factories.dart';

class MockSessionRepository extends Mock implements SessionRepository {}

// QA #373: el target semanal de Volumen por grupo debe respetar la
// periodización (isPresentInWeek) y la rutina de referencia de la SEMANA —
// no la de la última sesión de todo el historial. Espejo de los criterios
// de planProgressProvider (session_providers) y del fallback per-sesión de
// muscleDistributionInsightsProvider.
void main() {
  setUpAll(() {
    registerFallbackValue(makeSession());
    registerFallbackValue(makeSetLog());
  });

  /// Rutina Model B de 2 semanas: cuádriceps 3 sets en semana 0 y 5 sets en
  /// semana 1 (slots distintos por semana — el repro literal del issue).
  Routine makeModelBRoutine() => makeRoutine(
        id: 'r1',
        numWeeks: 2,
        days: [
          makeDay(slots: [
            makeSlot(
              exerciseId: 'e-squat-w0',
              muscleGroup: 'quads',
              targetSets: 3,
              activeWeeks: const [0],
            ),
            makeSlot(
              exerciseId: 'e-squat-w1',
              muscleGroup: 'quads',
              targetSets: 5,
              activeWeeks: const [1],
            ),
          ]),
        ],
      );

  ProviderContainer makeContainer(
    MockSessionRepository repo, {
    required Map<String, Routine?> routines,
  }) {
    final container = ProviderContainer(overrides: [
      currentUidProvider.overrideWithValue('u1'),
      sessionRepositoryProvider.overrideWithValue(repo),
      exercisesProvider.overrideWith((ref) async => const <Exercise>[]),
      for (final e in routines.entries)
        routineByIdProvider(e.key).overrideWith((ref) async => e.value),
      // [#442] el fallback de muscleGroup pasa por el resolver compartido,
      // que lee visibleRoutineByIdProvider (targets siguen en routineById).
      for (final e in routines.entries)
        visibleRoutineByIdProvider(e.key).overrideWith((ref) async => e.value),
    ]);
    addTearDown(container.dispose);
    return container;
  }

  test(
      'QA-373a: en semana 0 del plan, el target cuenta SOLO los slots de la '
      'semana 0 (no suma las demás semanas)', () async {
    final repo = MockSessionRepository();
    when(() => repo.listByUid('u1')).thenAnswer((_) async => [
          makeSession(
            id: 's1',
            startedAt: DateTime.now(),
            status: SessionStatus.finished,
            wasFullyCompleted: true,
            routineId: 'r1',
            weekNumber: 0,
          ),
        ]);
    when(() => repo.listSetLogs(uid: 'u1', sessionId: 's1'))
        .thenAnswer((_) async => []);

    final container =
        makeContainer(repo, routines: {'r1': makeModelBRoutine()});

    final result = await container.read(weeklyInsightsProvider.future);
    // Antes del fix: 3 + 5 = 8 (sobreestimado). Ahora: solo semana 0 → 3.
    expect(result!.targetByGroup[MuscleGroupDisplay.cuadriceps], 3);
  });

  test(
      'QA-373b: la semana del plan sale del weekNumber de la sesión de la '
      'semana calendario (semana 1 → target 5)', () async {
    final repo = MockSessionRepository();
    when(() => repo.listByUid('u1')).thenAnswer((_) async => [
          makeSession(
            id: 's1',
            startedAt: DateTime.now(),
            status: SessionStatus.finished,
            wasFullyCompleted: true,
            routineId: 'r1',
            weekNumber: 1,
          ),
        ]);
    when(() => repo.listSetLogs(uid: 'u1', sessionId: 's1'))
        .thenAnswer((_) async => []);

    final container =
        makeContainer(repo, routines: {'r1': makeModelBRoutine()});

    final result = await container.read(weeklyInsightsProvider.future);
    expect(result!.targetByGroup[MuscleGroupDisplay.cuadriceps], 5);
  });

  test(
      'QA-373c: semana calendario sin sesiones → semana activa derivada del '
      'plan (semana 0 completa en el historial → target de semana 1)',
      () async {
    final repo = MockSessionRepository();
    // Única sesión: vieja (fuera de la semana actual), completó la semana 0
    // del plan (day 1 es el único día requerido de la rutina de test).
    when(() => repo.listByUid('u1')).thenAnswer((_) async => [
          makeSession(
            id: 's-old',
            startedAt: DateTime.utc(2026, 5, 18, 15),
            status: SessionStatus.finished,
            wasFullyCompleted: true,
            routineId: 'r1',
            weekNumber: 0,
            dayNumber: 1,
          ),
        ]);
    when(() => repo.listSetLogs(uid: 'u1', sessionId: any(named: 'sessionId')))
        .thenAnswer((_) async => []);

    final container =
        makeContainer(repo, routines: {'r1': makeModelBRoutine()});

    final result = await container.read(weeklyInsightsProvider.future);
    // derivePlanProgress: semana 0 satisfecha → activeWeek == 1 → target 5.
    expect(result!.targetByGroup[MuscleGroupDisplay.cuadriceps], 5);
  });

  test(
      'QA-373d: el fallback de muscleGroup resuelve la rutina de CADA sesión '
      'de la semana — sets custom de una rutina reemplazada no se pierden',
      () async {
    final repo = MockSessionRepository();
    final now = DateTime.now();
    when(() => repo.listByUid('u1')).thenAnswer((_) async => [
          // Más reciente: rutina nueva r2 (referencia del target).
          makeSession(
            id: 's-new',
            startedAt: now,
            status: SessionStatus.finished,
            wasFullyCompleted: true,
            routineId: 'r2',
          ),
          // Anterior en la MISMA semana: rutina vieja r1 con ejercicio custom.
          makeSession(
            id: 's-prev',
            startedAt: now.subtract(const Duration(hours: 2)),
            status: SessionStatus.finished,
            wasFullyCompleted: true,
            routineId: 'r1',
          ),
        ]);
    when(() => repo.listSetLogs(uid: 'u1', sessionId: 's-new'))
        .thenAnswer((_) async => [
              makeSetLog(id: 'l1', exerciseId: 'e-new-custom', setNumber: 1),
            ]);
    when(() => repo.listSetLogs(uid: 'u1', sessionId: 's-prev'))
        .thenAnswer((_) async => [
              makeSetLog(id: 'l2', exerciseId: 'e-old-custom', setNumber: 1),
            ]);

    final r1 = makeRoutine(id: 'r1', days: [
      makeDay(slots: [
        makeSlot(exerciseId: 'e-old-custom', muscleGroup: 'back'),
      ]),
    ]);
    final r2 = makeRoutine(id: 'r2', days: [
      makeDay(slots: [
        makeSlot(exerciseId: 'e-new-custom', muscleGroup: 'chest'),
      ]),
    ]);

    final container = makeContainer(repo, routines: {'r1': r1, 'r2': r2});

    final result = await container.read(weeklyInsightsProvider.future);
    // Antes del fix solo se resolvía la rutina de la última sesión → el set
    // custom de r1 se descartaba en silencio.
    expect(result!.setsByGroup[MuscleGroupDisplay.espalda], 1);
    expect(result.setsByGroup[MuscleGroupDisplay.pecho], 1);
  });

  test(
      'QA-373e: regresión — rutina sin periodización (masks vacías) conserva '
      'el target completo', () async {
    final repo = MockSessionRepository();
    when(() => repo.listByUid('u1')).thenAnswer((_) async => [
          makeSession(
            id: 's1',
            startedAt: DateTime.now(),
            status: SessionStatus.finished,
            wasFullyCompleted: true,
            routineId: 'r1',
          ),
        ]);
    when(() => repo.listSetLogs(uid: 'u1', sessionId: 's1'))
        .thenAnswer((_) async => []);

    final routine = makeRoutine(id: 'r1', days: [
      makeDay(slots: [
        makeSlot(exerciseId: 'e1', muscleGroup: 'chest', targetSets: 3),
        makeSlot(exerciseId: 'e2', muscleGroup: 'chest', targetSets: 4),
      ]),
    ]);

    final container = makeContainer(repo, routines: {'r1': routine});

    final result = await container.read(weeklyInsightsProvider.future);
    expect(result!.targetByGroup[MuscleGroupDisplay.pecho], 7);
  });

  // ── QA #480: la rutina de referencia no visible degrada, no revienta ─────

  test(
      'QA-480a: rutina de referencia borrada/revocada → card renderiza sin '
      'target (no propaga permission-denied)', () async {
    final repo = MockSessionRepository();
    when(() => repo.listByUid('u1')).thenAnswer((_) async => [
          makeSession(
            id: 's1',
            startedAt: DateTime.now(),
            status: SessionStatus.finished,
            wasFullyCompleted: true,
            routineId: 'r-gone',
          ),
        ]);
    when(() => repo.listSetLogs(uid: 'u1', sessionId: 's1'))
        .thenAnswer((_) async => [
              // Set de un ejercicio del catálogo público: debe seguir
              // contando aunque la rutina de la sesión ya no exista.
              makeSetLog(id: 'l1', exerciseId: 'e-cat', setNumber: 1),
            ]);

    final container = ProviderContainer(overrides: [
      currentUidProvider.overrideWithValue('u1'),
      sessionRepositoryProvider.overrideWithValue(repo),
      exercisesProvider.overrideWith(
        (ref) async => const [
          Exercise(
            id: 'e-cat',
            name: 'Press banca',
            muscleGroup: 'chest',
            category: 'compound',
          ),
        ],
      ),
      // getByIdIfVisible contract: borrada/sin acceso → null (NO lanza).
      visibleRoutineByIdProvider('r-gone').overrideWith((ref) async => null),
    ]);
    addTearDown(container.dispose);

    final result = await container.read(weeklyInsightsProvider.future);
    expect(result, isNotNull,
        reason: 'Una rutina no visible no puede tirar la card entera');
    expect(result!.targetByGroup, isEmpty,
        reason: 'Sin rutina de referencia → sin target (camino existente)');
    expect(result.setsByGroup[MuscleGroupDisplay.pecho], 1,
        reason: 'Los sets del catálogo público siguen contando');
  });

  test(
      'QA-480b: falla transiente del fetch de referencia SÍ propaga '
      '(error state legítimo)', () async {
    final repo = MockSessionRepository();
    when(() => repo.listByUid('u1')).thenAnswer((_) async => [
          makeSession(
            id: 's1',
            startedAt: DateTime.now(),
            status: SessionStatus.finished,
            wasFullyCompleted: true,
            routineId: 'r-flaky',
          ),
        ]);
    when(() => repo.listSetLogs(uid: 'u1', sessionId: 's1'))
        .thenAnswer((_) async => []);

    final container = ProviderContainer(overrides: [
      currentUidProvider.overrideWithValue('u1'),
      sessionRepositoryProvider.overrideWithValue(repo),
      exercisesProvider.overrideWith((ref) async => const <Exercise>[]),
      visibleRoutineByIdProvider('r-flaky')
          .overrideWith((ref) async => throw Exception('backend down')),
    ]);
    addTearDown(container.dispose);

    await expectLater(
      container.read(weeklyInsightsProvider.future),
      throwsException,
    );
  });
}
