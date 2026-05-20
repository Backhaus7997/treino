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
import 'package:treino/features/workout/domain/session_status.dart';
import 'package:treino/features/workout/domain/set_log.dart';

import '../../workout/application/stub_factories.dart';

class MockSessionRepository extends Mock implements SessionRepository {}

Exercise _ex({
  required String id,
  required String muscleGroup,
  String name = 'Exercise',
}) =>
    Exercise(
      id: id,
      name: name,
      muscleGroup: muscleGroup,
      category: 'compound',
    );

void main() {
  setUpAll(() {
    registerFallbackValue(makeSession());
    registerFallbackValue(makeSetLog());
  });

  // Lunes 18 may 2026 00:00 local — la semana actual usada por todos los
  // tests (alineada con stub_factories.makeSession default startedAt).
  // NOTE: el provider usa DateTime.now() — los tests no pueden controlar
  // ese reloj sin inyectarlo. Por eso los tests se ejecutan asumiendo que
  // la semana actual contiene 2026-05-18 (verificado en el momento de
  // escribir). Si el calendario cambia, este día queda fuera de semana y
  // los aggregates devuelven 0 — los tests detectarían esa drift.

  group('weeklyInsightsProvider', () {
    test('SCENARIO-401: returns null when uid is null', () async {
      final container = ProviderContainer(overrides: [
        currentUidProvider.overrideWithValue(null),
      ]);
      addTearDown(container.dispose);

      final result = await container.read(weeklyInsightsProvider.future);
      expect(result, isNull);
    });

    test('SCENARIO-402: returns insights with all empty when no sessions',
        () async {
      final repo = MockSessionRepository();
      when(() => repo.listByUid('u1')).thenAnswer((_) async => const []);

      final container = ProviderContainer(overrides: [
        currentUidProvider.overrideWithValue('u1'),
        sessionRepositoryProvider.overrideWithValue(repo),
        exercisesProvider.overrideWith((ref) async => const <Exercise>[]),
      ]);
      addTearDown(container.dispose);

      final result = await container.read(weeklyInsightsProvider.future);
      expect(result, isNotNull);
      expect(result!.sessionsCount, 0);
      expect(result.daysTrained, equals(List<bool>.filled(7, false)));
      expect(result.setsByGroup, isEmpty);
      expect(result.targetByGroup, isEmpty);
      expect(result.plannedSessionsCount, 5);
    });

    test('SCENARIO-403: filtra sesiones por status=finished', () async {
      final repo = MockSessionRepository();
      // 1 active (excluida) + 1 finished
      final now = DateTime.now();
      when(() => repo.listByUid('u1')).thenAnswer((_) async => [
            makeSession(
              id: 's-active',
              startedAt: now,
              status: SessionStatus.active,
            ),
            makeSession(
              id: 's-finished',
              startedAt: now,
              status: SessionStatus.finished,
              routineId: 'r1',
            ),
          ]);
      when(() => repo.listSetLogs(uid: 'u1', sessionId: 's-finished'))
          .thenAnswer((_) async => const []);

      final container = ProviderContainer(overrides: [
        currentUidProvider.overrideWithValue('u1'),
        sessionRepositoryProvider.overrideWithValue(repo),
        exercisesProvider.overrideWith((ref) async => const <Exercise>[]),
        routineByIdProvider('r1').overrideWith((ref) async => null),
      ]);
      addTearDown(container.dispose);

      final result = await container.read(weeklyInsightsProvider.future);
      expect(result!.sessionsCount, 1);
      verifyNever(() => repo.listSetLogs(uid: 'u1', sessionId: 's-active'));
    });

    test('SCENARIO-404: agrupa SetLogs por muscleGroup → MuscleGroupDisplay',
        () async {
      final repo = MockSessionRepository();
      final now = DateTime.now();
      when(() => repo.listByUid('u1')).thenAnswer((_) async => [
            makeSession(
              id: 's1',
              startedAt: now,
              status: SessionStatus.finished,
              routineId: 'r1',
            ),
          ]);
      // 3 sets de chest + 2 de quads + 1 de biceps + 1 de muscleGroup desconocido (skipped)
      when(() => repo.listSetLogs(uid: 'u1', sessionId: 's1'))
          .thenAnswer((_) async => [
                makeSetLog(id: 'l1', exerciseId: 'e-chest', setNumber: 1),
                makeSetLog(id: 'l2', exerciseId: 'e-chest', setNumber: 2),
                makeSetLog(id: 'l3', exerciseId: 'e-chest', setNumber: 3),
                makeSetLog(id: 'l4', exerciseId: 'e-quads', setNumber: 1),
                makeSetLog(id: 'l5', exerciseId: 'e-quads', setNumber: 2),
                makeSetLog(id: 'l6', exerciseId: 'e-biceps', setNumber: 1),
                makeSetLog(id: 'l7', exerciseId: 'e-unknown', setNumber: 1),
              ]);

      final container = ProviderContainer(overrides: [
        currentUidProvider.overrideWithValue('u1'),
        sessionRepositoryProvider.overrideWithValue(repo),
        exercisesProvider.overrideWith((ref) async => [
              _ex(id: 'e-chest', muscleGroup: 'chest'),
              _ex(id: 'e-quads', muscleGroup: 'quads'),
              _ex(id: 'e-biceps', muscleGroup: 'biceps'),
              _ex(id: 'e-unknown', muscleGroup: 'unknownGroup'),
            ]),
        routineByIdProvider('r1').overrideWith((ref) async => null),
      ]);
      addTearDown(container.dispose);

      final result = await container.read(weeklyInsightsProvider.future);
      expect(result!.setsByGroup[MuscleGroupDisplay.pecho], 3);
      expect(result.setsByGroup[MuscleGroupDisplay.piernas], 2);
      expect(result.setsByGroup[MuscleGroupDisplay.brazos], 1);
      // El log de 'unknownGroup' fue descartado defensivamente.
      expect(
          result.setsByGroup.containsKey(MuscleGroupDisplay.espalda), isFalse);
    });

    test('SCENARIO-405: daysTrained refleja qué días de la semana hubo sesión',
        () async {
      final repo = MockSessionRepository();
      // 2 sesiones: una lunes (weekday=1) y una miércoles (weekday=3) de
      // esta semana — usamos lookback desde hoy para mantener el test
      // independiente de la fecha del calendario.
      final now = DateTime.now();
      // Monday of this week
      final mondayOfWeek = DateTime(now.year, now.month, now.day)
          .subtract(Duration(days: now.weekday - DateTime.monday));
      final monday = mondayOfWeek.add(const Duration(hours: 10));
      final wednesday = mondayOfWeek.add(const Duration(days: 2, hours: 10));

      when(() => repo.listByUid('u1')).thenAnswer((_) async => [
            makeSession(
              id: 's-mon',
              startedAt: monday,
              status: SessionStatus.finished,
              routineId: 'r1',
            ),
            makeSession(
              id: 's-wed',
              startedAt: wednesday,
              status: SessionStatus.finished,
              routineId: 'r1',
            ),
          ]);
      when(() =>
              repo.listSetLogs(uid: 'u1', sessionId: any(named: 'sessionId')))
          .thenAnswer(
        (_) async => const <SetLog>[],
      );

      final container = ProviderContainer(overrides: [
        currentUidProvider.overrideWithValue('u1'),
        sessionRepositoryProvider.overrideWithValue(repo),
        exercisesProvider.overrideWith((ref) async => const <Exercise>[]),
        routineByIdProvider('r1').overrideWith((ref) async => null),
      ]);
      addTearDown(container.dispose);

      final result = await container.read(weeklyInsightsProvider.future);
      // Index 0=lun, 2=mié.
      expect(result!.daysTrained[0], isTrue);
      expect(result.daysTrained[1], isFalse);
      expect(result.daysTrained[2], isTrue);
      for (var i = 3; i < 7; i++) {
        expect(result.daysTrained[i], isFalse);
      }
      expect(result.sessionsCount, 2);
    });

    test(
        'SCENARIO-406: targetByGroup viene de la rutina de la sesión más reciente',
        () async {
      final repo = MockSessionRepository();
      final now = DateTime.now();
      when(() => repo.listByUid('u1')).thenAnswer((_) async => [
            makeSession(
              id: 's1',
              startedAt: now,
              status: SessionStatus.finished,
              routineId: 'r1',
            ),
          ]);
      when(() => repo.listSetLogs(uid: 'u1', sessionId: 's1'))
          .thenAnswer((_) async => const []);

      final routine = makeRoutine(
        id: 'r1',
        days: [
          makeDay(slots: [
            makeSlot(exerciseId: 'e-chest', targetSets: 4),
            makeSlot(exerciseId: 'e-back', targetSets: 3),
          ]),
          makeDay(dayNumber: 2, slots: [
            makeSlot(exerciseId: 'e-quads', targetSets: 5),
            makeSlot(exerciseId: 'e-glutes', targetSets: 3),
          ]),
        ],
      );

      final container = ProviderContainer(overrides: [
        currentUidProvider.overrideWithValue('u1'),
        sessionRepositoryProvider.overrideWithValue(repo),
        exercisesProvider.overrideWith((ref) async => [
              _ex(id: 'e-chest', muscleGroup: 'chest'),
              _ex(id: 'e-back', muscleGroup: 'back'),
              _ex(id: 'e-quads', muscleGroup: 'quads'),
              _ex(id: 'e-glutes', muscleGroup: 'glutes'),
            ]),
        routineByIdProvider('r1').overrideWith((ref) async => routine),
      ]);
      addTearDown(container.dispose);

      final result = await container.read(weeklyInsightsProvider.future);
      expect(result!.targetByGroup[MuscleGroupDisplay.pecho], 4);
      expect(result.targetByGroup[MuscleGroupDisplay.espalda], 3);
      // quads + glutes ambos mapean a piernas → 5 + 3 = 8
      expect(result.targetByGroup[MuscleGroupDisplay.piernas], 8);
    });
  });
}
