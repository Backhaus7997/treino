// Tests de aggregateSessionHighlights + sessionHighlightsProvider — récords
// REALES del resumen post-entreno comparando la sesión contra el historial.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/features/workout/application/exercise_progression_providers.dart'
    show kProgressionSessionScan;
import 'package:treino/features/workout/application/session_highlights.dart';
import 'package:treino/features/workout/application/session_providers.dart';
import 'package:treino/features/workout/application/session_recognition.dart';
import 'package:treino/features/workout/data/session_repository.dart';
import 'package:treino/features/workout/domain/exercise_progression.dart';
import 'package:treino/features/workout/domain/session.dart';
import 'package:treino/features/workout/domain/session_status.dart';
import 'package:treino/features/workout/domain/set_log.dart';

class _MockSessionRepository extends Mock implements SessionRepository {}

Session _session({
  String id = 's-hoy',
  DateTime? startedAt,
  double totalVolumeKg = 1000,
  bool wasFullyCompleted = true,
}) =>
    Session(
      id: id,
      uid: 'u1',
      routineId: 'r1',
      routineName: 'Push',
      startedAt: startedAt ?? DateTime.utc(2026, 5, 18, 10),
      status: SessionStatus.finished,
      wasFullyCompleted: wasFullyCompleted,
      totalVolumeKg: totalVolumeKg,
    );

SetLog _log(
  String exerciseId, {
  String? name,
  int setNumber = 1,
  int reps = 5,
  double weightKg = 60,
}) =>
    SetLog(
      id: '$exerciseId-$setNumber-$reps-$weightKg',
      exerciseId: exerciseId,
      exerciseName: name ?? 'Ejercicio $exerciseId',
      setNumber: setNumber,
      reps: reps,
      weightKg: weightKg,
      completedAt: DateTime.utc(2026, 5, 18, 10, 5),
    );

final _now = DateTime.utc(2026, 5, 18, 13);

void main() {
  group('aggregateSessionHighlights — récords', () {
    test('subir el peso máximo bate los 3 tipos por-set (peso, 1RM, serie)',
        () {
      final session = _session();
      final prior =
          _session(id: 'p1', startedAt: DateTime.utc(2026, 5, 11, 10));

      final result = aggregateSessionHighlights(
        session: session,
        sessionLogs: [_log('e1', reps: 5, weightKg: 80)],
        sessionsDesc: [session, prior],
        priorLogsBySession: {
          'p1': [_log('e1', reps: 5, weightKg: 75)],
        },
        now: _now,
      );

      expect(result.recordCount, 3);
      final records = result.exercises.single.records;
      final byType = {for (final r in records) r.recordType: r};
      expect(byType[ProgressionRecordType.heaviestWeight]?.value, 80);
      expect(byType[ProgressionRecordType.heaviestWeight]?.previousBest, 75);
      expect(byType[ProgressionRecordType.bestSetVolume]?.value, 400);
      expect(byType[ProgressionRecordType.bestSetVolume]?.previousBest, 375);
      // Epley: 80·(1+5/30) vs 75·(1+5/30).
      expect(
        byType[ProgressionRecordType.oneRepMax]?.value,
        closeTo(80 * (1 + 5 / 30.0), 0.001),
      );
      expect(result.recognition.kind, SessionRecognitionKind.records);
      expect(result.recognition.count, 3);
    });

    test('más reps al mismo peso bate 1RM y mejor serie, NO peso máximo', () {
      final session = _session();
      final prior =
          _session(id: 'p1', startedAt: DateTime.utc(2026, 5, 11, 10));

      final result = aggregateSessionHighlights(
        session: session,
        sessionLogs: [_log('e1', reps: 8, weightKg: 80)],
        sessionsDesc: [session, prior],
        priorLogsBySession: {
          'p1': [_log('e1', reps: 5, weightKg: 80)],
        },
        now: _now,
      );

      final types =
          result.exercises.single.records.map((r) => r.recordType).toSet();
      expect(types, {
        ProgressionRecordType.oneRepMax,
        ProgressionRecordType.bestSetVolume,
      });
      expect(result.recordCount, 2);
    });

    test('repetir exactamente la marca previa NO es récord (estrictamente >)',
        () {
      final session = _session();
      final prior = _session(id: 'p1', startedAt: DateTime.utc(2026, 4, 6, 10));

      final result = aggregateSessionHighlights(
        session: session,
        sessionLogs: [_log('e1', reps: 5, weightKg: 80)],
        sessionsDesc: [session, prior],
        priorLogsBySession: {
          'p1': [_log('e1', reps: 5, weightKg: 80)],
        },
        now: _now,
      );

      expect(result.recordCount, 0);
      expect(result.exercises.single.records, isEmpty);
      expect(result.hasHistory, isTrue);
    });

    test(
        'el mejor histórico se toma sobre TODO el scan, no solo la última '
        'sesión', () {
      final session = _session();
      final priorRecent =
          _session(id: 'p1', startedAt: DateTime.utc(2026, 5, 11, 10));
      final priorOld =
          _session(id: 'p2', startedAt: DateTime.utc(2026, 4, 6, 10));

      final result = aggregateSessionHighlights(
        session: session,
        // 82.5 supera la última sesión (70) pero NO el máximo histórico (85).
        sessionLogs: [_log('e1', reps: 5, weightKg: 82.5)],
        sessionsDesc: [session, priorRecent, priorOld],
        priorLogsBySession: {
          'p1': [_log('e1', reps: 5, weightKg: 70)],
          'p2': [_log('e1', reps: 5, weightKg: 85)],
        },
        now: _now,
      );

      expect(
        result.exercises.single.records
            .where((r) => r.recordType == ProgressionRecordType.heaviestWeight),
        isEmpty,
      );
    });

    test('sesión abandonada (#372): filas sí, récords y reconocimiento no', () {
      final session = _session(wasFullyCompleted: false);
      final prior =
          _session(id: 'p1', startedAt: DateTime.utc(2026, 5, 11, 10));

      final result = aggregateSessionHighlights(
        session: session,
        sessionLogs: [_log('e1', reps: 5, weightKg: 90)],
        sessionsDesc: [session, prior],
        priorLogsBySession: {
          'p1': [_log('e1', reps: 5, weightKg: 75)],
        },
        now: _now,
      );

      expect(result.exercises, hasLength(1));
      expect(result.exercises.single.setCount, 1);
      expect(result.recordCount, 0);
      expect(result.exercises.single.records, isEmpty);
      expect(result.exercises.single.isFirstTime, isFalse);
      expect(result.recognition.kind, SessionRecognitionKind.none);
    });

    test(
        'historial previo solo-bodyweight (#368): sin marca previa no hay '
        'récord ni 1ª vez', () {
      final session = _session();
      final prior =
          _session(id: 'p1', startedAt: DateTime.utc(2026, 5, 11, 10));

      final result = aggregateSessionHighlights(
        session: session,
        sessionLogs: [_log('e1', reps: 8, weightKg: 40)],
        sessionsDesc: [session, prior],
        priorLogsBySession: {
          // Dominadas al peso corporal: 0 kg → ninguna serie histórica.
          'p1': [_log('e1', reps: 12, weightKg: 0)],
        },
        now: _now,
      );

      expect(result.exercises.single.records, isEmpty);
      expect(result.exercises.single.isFirstTime, isFalse);
    });
  });

  group('aggregateSessionHighlights — filas y primeras veces', () {
    test('sin historia: hasHistory false, firstWorkout, sin badges 1ª vez', () {
      final session = _session();

      final result = aggregateSessionHighlights(
        session: session,
        sessionLogs: [_log('e1', reps: 5, weightKg: 60)],
        sessionsDesc: [session],
        priorLogsBySession: const {},
        now: _now,
      );

      expect(result.hasHistory, isFalse);
      expect(result.recordCount, 0);
      expect(result.exercises.single.isFirstTime, isFalse);
      expect(result.recognition.kind, SessionRecognitionKind.firstWorkout);
    });

    test('ejercicio nuevo con historia de otros → 1ª vez, sin récords', () {
      final session = _session();
      final prior =
          _session(id: 'p1', startedAt: DateTime.utc(2026, 5, 11, 10));

      final result = aggregateSessionHighlights(
        session: session,
        sessionLogs: [
          _log('e1', reps: 5, weightKg: 80),
          _log('nuevo', reps: 10, weightKg: 20),
        ],
        sessionsDesc: [session, prior],
        priorLogsBySession: {
          'p1': [_log('e1', reps: 5, weightKg: 80)],
        },
        now: _now,
      );

      final nuevo =
          result.exercises.singleWhere((e) => e.exerciseId == 'nuevo');
      expect(nuevo.isFirstTime, isTrue);
      expect(nuevo.records, isEmpty);
      final conocido =
          result.exercises.singleWhere((e) => e.exerciseId == 'e1');
      expect(conocido.isFirstTime, isFalse);
    });

    test(
        'con el scan lleno (>= kProgressionSessionScan previas) la 1ª vez '
        'se suprime: ausencia del scan no prueba "nunca"', () {
      final session = _session();
      final priors = List.generate(
        kProgressionSessionScan,
        (i) => _session(
          id: 'p$i',
          startedAt: DateTime.utc(2026, 4, 1).subtract(Duration(days: i)),
        ),
      );

      final result = aggregateSessionHighlights(
        session: session,
        sessionLogs: [_log('nuevo', reps: 10, weightKg: 20)],
        sessionsDesc: [session, ...priors],
        priorLogsBySession: {
          for (final p in priors) p.id: [_log('e1', reps: 5, weightKg: 80)],
        },
        now: _now,
      );

      expect(result.exercises.single.isFirstTime, isFalse);
    });

    test('filas: orden de primera aparición, sets, mejor set y volumen', () {
      final session = _session();

      final result = aggregateSessionHighlights(
        session: session,
        sessionLogs: [
          _log('e1', setNumber: 1, reps: 8, weightKg: 60),
          _log('e2', setNumber: 1, reps: 12, weightKg: 0),
          // Mismo peso que el set 1 con más reps → mejor set por desempate.
          _log('e1', setNumber: 2, reps: 10, weightKg: 60),
        ],
        sessionsDesc: [session],
        priorLogsBySession: const {},
        now: _now,
      );

      expect(result.exercises.map((e) => e.exerciseId).toList(), ['e1', 'e2']);

      final e1 = result.exercises.first;
      expect(e1.setCount, 2);
      expect(e1.bestWeightKg, 60);
      expect(e1.bestSetReps, 10);
      expect(e1.sessionVolumeKg, 8 * 60 + 10 * 60);

      // Solo-bodyweight: mejor set por reps con peso 0, volumen 0 (#368).
      final e2 = result.exercises.last;
      expect(e2.setCount, 1);
      expect(e2.bestWeightKg, 0);
      expect(e2.bestSetReps, 12);
      expect(e2.sessionVolumeKg, 0);
    });
  });

  group('sessionHighlightsProvider', () {
    test('uid vacío → vacío sin leer nada', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final result = await container.read(
        sessionHighlightsProvider((uid: '', sessionId: 's1')).future,
      );

      expect(result, emptySessionHighlights);
    });

    test(
        'fan-out acotado: con 70 previas solo se leen logs de 60 (el tope '
        'compartido, no por-ejercicio)', () async {
      final repo = _MockSessionRepository();
      when(() => repo.listSetLogs(
            uid: any(named: 'uid'),
            sessionId: any(named: 'sessionId'),
          )).thenAnswer((_) async => [_log('e1', reps: 5, weightKg: 75)]);

      final session = _session();
      final priors = List.generate(
        70,
        (i) => _session(
          id: 'p$i',
          startedAt: DateTime.utc(2026, 4, 1).subtract(Duration(days: i)),
        ),
      );

      final container = ProviderContainer(
        overrides: [
          sessionRepositoryProvider.overrideWithValue(repo),
          sessionSummaryProvider.overrideWith(
            (ref, key) async => (
              session: session,
              setLogs: [
                _log('e1', reps: 5, weightKg: 80),
                _log('e2', reps: 8, weightKg: 40),
              ],
            ),
          ),
          sessionsByUidProvider.overrideWith(
            (ref, uid) async => [session, ...priors],
          ),
        ],
      );
      addTearDown(container.dispose);

      final result = await container.read(
        sessionHighlightsProvider((uid: 'u1', sessionId: session.id)).future,
      );

      verify(() => repo.listSetLogs(
            uid: any(named: 'uid'),
            sessionId: any(named: 'sessionId'),
          )).called(kProgressionSessionScan);

      // e1 batió el 75 histórico; e2 no existe en el historial → sin récord.
      expect(result.recordCount, greaterThan(0));
      expect(result.exercises, hasLength(2));
    });

    test('sesión que no cuenta: el fan-out de logs se saltea por completo',
        () async {
      final repo = _MockSessionRepository();

      final session = _session(wasFullyCompleted: false);
      final prior =
          _session(id: 'p1', startedAt: DateTime.utc(2026, 5, 11, 10));

      final container = ProviderContainer(
        overrides: [
          sessionRepositoryProvider.overrideWithValue(repo),
          sessionSummaryProvider.overrideWith(
            (ref, key) async => (
              session: session,
              setLogs: [_log('e1', reps: 5, weightKg: 90)],
            ),
          ),
          sessionsByUidProvider.overrideWith(
            (ref, uid) async => [session, prior],
          ),
        ],
      );
      addTearDown(container.dispose);

      final result = await container.read(
        sessionHighlightsProvider((uid: 'u1', sessionId: session.id)).future,
      );

      verifyNever(() => repo.listSetLogs(
            uid: any(named: 'uid'),
            sessionId: any(named: 'sessionId'),
          ));
      expect(result.exercises, hasLength(1));
      expect(result.recordCount, 0);
    });

    test('sesión sin sets → vacío', () async {
      final container = ProviderContainer(
        overrides: [
          sessionSummaryProvider.overrideWith(
            (ref, key) async => (session: _session(), setLogs: <SetLog>[]),
          ),
        ],
      );
      addTearDown(container.dispose);

      final result = await container.read(
        sessionHighlightsProvider((uid: 'u1', sessionId: 's-hoy')).future,
      );

      expect(result, emptySessionHighlights);
    });
  });
}
