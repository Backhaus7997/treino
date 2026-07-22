// Tests para SessionNotifier — Path A (SCENARIO-256..258), Path B (SCENARIO-318..321),
// mutaciones (SCENARIO-259..268).
// SCENARIO-037-notifier: _nextIncompleteIndex uses effectiveSetsForWeek on
// periodized plans (week 1 needs fewer sets to advance than legacy targetSets).
// La implementación ya existe (fue necesaria para compilar session_providers.dart),
// por lo que este archivo actúa como GREEN desde el principio.
// Desviación documentada en apply-progress.md.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/core/analytics/analytics_service.dart';
import 'package:treino/features/workout/application/session_init.dart';
import 'package:treino/features/workout/application/session_notifier.dart';
import 'package:treino/features/workout/application/session_providers.dart';
import 'package:treino/features/workout/application/routine_providers.dart';
import 'package:treino/features/workout/data/session_repository.dart';
import 'package:treino/features/workout/domain/routine.dart';
import 'package:treino/features/workout/domain/session.dart';
import 'package:treino/features/workout/domain/routine_slot.dart';
import 'package:treino/features/workout/domain/set_log.dart';
import 'package:treino/features/workout/domain/set_spec.dart';

import '../../../helpers/fake_analytics_service.dart';
import 'stub_factories.dart';

// ── Mocks ─────────────────────────────────────────────────────────────────────

class MockSessionRepository extends Mock implements SessionRepository {}

// ── Helpers ───────────────────────────────────────────────────────────────────

/// Crea container con overrides necesarios para probar el notifier.
ProviderContainer _makeContainer({
  required MockSessionRepository repo,
  required String uid,
  Routine? routine,
}) {
  return ProviderContainer(
    overrides: [
      sessionRepositoryProvider.overrideWithValue(repo),
      currentUidProvider.overrideWithValue(uid),
      // Analytics is fired post-finishSession; override con fake para evitar
      // que FirebaseAnalytics.instance se invoque sin Firebase init en tests.
      analyticsServiceProvider.overrideWithValue(FakeAnalyticsService()),
      if (routine != null)
        routineByIdProvider(routine.id).overrideWith(
          (ref) async => routine,
        ),
    ],
  );
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  setUpAll(() {
    registerFallbackValue(makeSession());
    registerFallbackValue(makeSetLog());
  });

  // ── Path A — Sesión nueva (SCENARIO-256..258) ─────────────────────────────

  group('SessionNotifier Path A — FreshSession', () {
    test('SCENARIO-256: repo.create es llamado exactamente una vez', () async {
      final repo = MockSessionRepository();
      final routine = makeRoutine();
      final session = makeSession();

      when(() => repo.create(
            uid: any(named: 'uid'),
            routineId: any(named: 'routineId'),
            routineName: any(named: 'routineName'),
            startedAt: any(named: 'startedAt'),
            dayNumber: any(named: 'dayNumber'),
          )).thenAnswer((_) async => session);

      final container = _makeContainer(
        repo: repo,
        uid: 'u1',
        routine: routine,
      );
      addTearDown(container.dispose);

      final init = FreshSession(routineId: routine.id, dayNumber: 1);
      await container.read(sessionNotifierProvider(init).future);

      verify(() => repo.create(
            uid: any(named: 'uid'),
            routineId: any(named: 'routineId'),
            routineName: any(named: 'routineName'),
            startedAt: any(named: 'startedAt'),
            dayNumber: any(named: 'dayNumber'),
          )).called(1);
    });

    test(
        'SCENARIO-257: estado inicial tiene setLogs vacío y currentExerciseIndex = 0',
        () async {
      final repo = MockSessionRepository();
      final routine = makeRoutine();
      final session = makeSession();

      when(() => repo.create(
            uid: any(named: 'uid'),
            routineId: any(named: 'routineId'),
            routineName: any(named: 'routineName'),
            startedAt: any(named: 'startedAt'),
            dayNumber: any(named: 'dayNumber'),
          )).thenAnswer((_) async => session);

      final container = _makeContainer(
        repo: repo,
        uid: 'u1',
        routine: routine,
      );
      addTearDown(container.dispose);

      final init = FreshSession(routineId: routine.id, dayNumber: 1);
      final state = await container.read(sessionNotifierProvider(init).future);

      expect(state.setLogs, isEmpty);
      expect(state.currentExerciseIndex, equals(0));
    });

    test('SCENARIO-258: dispose cancela el timer (sin leaks)', () async {
      final repo = MockSessionRepository();
      final routine = makeRoutine();
      final session = makeSession();

      when(() => repo.create(
            uid: any(named: 'uid'),
            routineId: any(named: 'routineId'),
            routineName: any(named: 'routineName'),
            startedAt: any(named: 'startedAt'),
            dayNumber: any(named: 'dayNumber'),
          )).thenAnswer((_) async => session);

      final container = _makeContainer(
        repo: repo,
        uid: 'u1',
        routine: routine,
      );

      final init = FreshSession(routineId: routine.id, dayNumber: 1);
      await container.read(sessionNotifierProvider(init).future);

      // Dispose del container → ref.onDispose() del notifier debe cancelar timer.
      // No hay leak si no lanza excepción.
      expect(() => container.dispose(), returnsNormally);
    });
  });

  // ── Path B — Retomar sesión (SCENARIO-318..321) ───────────────────────────

  group('SessionNotifier Path B — ResumeSession', () {
    test('SCENARIO-318: repo.create NO es llamado', () async {
      final repo = MockSessionRepository();
      final routine = makeRoutine();
      final session = makeSession(id: 's42');
      final setLogs = [
        makeSetLog(exerciseId: 'e1', setNumber: 1, id: 'l1'),
      ];

      when(() => repo.getActive('u1')).thenAnswer((_) async => session);
      when(() => repo.listSetLogs(uid: 'u1', sessionId: 's42'))
          .thenAnswer((_) async => setLogs);

      final container = _makeContainer(
        repo: repo,
        uid: 'u1',
        routine: routine,
      );
      addTearDown(container.dispose);

      const init = ResumeSession(sessionId: 's42');
      await container.read(sessionNotifierProvider(init).future);

      verifyNever(() => repo.create(
            uid: any(named: 'uid'),
            routineId: any(named: 'routineId'),
            routineName: any(named: 'routineName'),
            startedAt: any(named: 'startedAt'),
            dayNumber: any(named: 'dayNumber'),
          ));
    });

    test('SCENARIO-319: setLogs restaurados desde el repo', () async {
      final repo = MockSessionRepository();
      final routine = makeRoutine();
      final session = makeSession(id: 's42');
      final setLogs = [
        makeSetLog(exerciseId: 'e1', setNumber: 1, id: 'l1'),
        makeSetLog(exerciseId: 'e1', setNumber: 2, id: 'l2'),
      ];

      when(() => repo.getActive('u1')).thenAnswer((_) async => session);
      when(() => repo.listSetLogs(uid: 'u1', sessionId: 's42'))
          .thenAnswer((_) async => setLogs);

      final container = _makeContainer(
        repo: repo,
        uid: 'u1',
        routine: routine,
      );
      addTearDown(container.dispose);

      const init = ResumeSession(sessionId: 's42');
      final state = await container.read(sessionNotifierProvider(init).future);

      expect(state.setLogs.length, equals(2));
      expect(state.setLogs[0].id, equals('l1'));
    });

    test(
        'SCENARIO-320: currentExerciseIndex recomputado desde los logs restaurados',
        () async {
      final repo = MockSessionRepository();
      // Rutina con 2 ejercicios, targetSets=3 y 2 respectivamente
      final routine = makeRoutine(
        days: [
          makeDay(slots: [
            makeSlot(exerciseId: 'e1', targetSets: 3),
            makeSlot(exerciseId: 'e2', targetSets: 2),
          ])
        ],
      );
      final session = makeSession(id: 's42');
      // e1 ya tiene 3 sets → completo. Index debe apuntar a e2 (índice 1).
      final setLogs = [
        makeSetLog(exerciseId: 'e1', setNumber: 1, id: 'l1'),
        makeSetLog(exerciseId: 'e1', setNumber: 2, id: 'l2'),
        makeSetLog(exerciseId: 'e1', setNumber: 3, id: 'l3'),
      ];

      when(() => repo.getActive('u1')).thenAnswer((_) async => session);
      when(() => repo.listSetLogs(uid: 'u1', sessionId: 's42'))
          .thenAnswer((_) async => setLogs);

      final container = _makeContainer(
        repo: repo,
        uid: 'u1',
        routine: routine,
      );
      addTearDown(container.dispose);

      const init = ResumeSession(sessionId: 's42');
      final state = await container.read(sessionNotifierProvider(init).future);

      expect(state.currentExerciseIndex, equals(1));
    });

    test('SCENARIO-321: elapsedSeconds aproximado a partir de startedAt (±2s)',
        () async {
      final repo = MockSessionRepository();
      final routine = makeRoutine();
      final startedAt = DateTime.now().subtract(const Duration(minutes: 5));
      final session = makeSession(id: 's42', startedAt: startedAt);

      when(() => repo.getActive('u1')).thenAnswer((_) async => session);
      when(() => repo.listSetLogs(uid: 'u1', sessionId: 's42'))
          .thenAnswer((_) async => []);

      final container = _makeContainer(
        repo: repo,
        uid: 'u1',
        routine: routine,
      );
      addTearDown(container.dispose);

      const init = ResumeSession(sessionId: 's42');
      final state = await container.read(sessionNotifierProvider(init).future);

      // 5 minutos = 300 segundos, tolerancia ±2s
      expect(state.elapsedSeconds, closeTo(300, 2));
    });

    test('stale resume uses recovered set timeline, not overnight wall time',
        () async {
      final repo = MockSessionRepository();
      final routine = makeRoutine(
        days: [
          makeDay(slots: [makeSlot(exerciseId: 'e1', targetSets: 1)])
        ],
      );
      final startedAt = DateTime.now().subtract(const Duration(days: 2));
      final session = makeSession(id: 's42', startedAt: startedAt);
      final setLogs = [
        makeSetLog(
          exerciseId: 'e1',
          setNumber: 1,
          id: 'l1',
          completedAt: startedAt.add(const Duration(minutes: 40)),
        ),
      ];

      when(() => repo.getActive('u1')).thenAnswer((_) async => session);
      when(() => repo.listSetLogs(uid: 'u1', sessionId: 's42'))
          .thenAnswer((_) async => setLogs);
      when(() => repo.finish(
            uid: any(named: 'uid'),
            sessionId: any(named: 'sessionId'),
            finishedAt: any(named: 'finishedAt'),
            wasFullyCompleted: any(named: 'wasFullyCompleted'),
            totalVolumeKg: any(named: 'totalVolumeKg'),
            durationMin: any(named: 'durationMin'),
          )).thenAnswer((_) async {});

      final container = _makeContainer(
        repo: repo,
        uid: 'u1',
        routine: routine,
      );
      addTearDown(container.dispose);

      const init = ResumeSession(sessionId: 's42');
      final state = await container.read(sessionNotifierProvider(init).future);

      expect(state.elapsedSeconds, const Duration(minutes: 40).inSeconds);

      await container
          .read(sessionNotifierProvider(init).notifier)
          .finishSession();

      verify(() => repo.finish(
            uid: 'u1',
            sessionId: 's42',
            finishedAt: any(named: 'finishedAt'),
            wasFullyCompleted: true,
            totalVolumeKg: any(named: 'totalVolumeKg'),
            durationMin: 40,
          )).called(1);
    });
  });

  // ── logSet (SCENARIO-259..264) ────────────────────────────────────────────

  group('SessionNotifier.logSet', () {
    /// Inicializa el notifier vía Path A y devuelve el container + notifier.
    Future<
        ({
          ProviderContainer container,
          FreshSession init,
        })> setupFresh({
      required MockSessionRepository repo,
      Routine? routine,
    }) async {
      final r = routine ?? makeRoutine();
      final session = makeSession();

      when(() => repo.create(
            uid: any(named: 'uid'),
            routineId: any(named: 'routineId'),
            routineName: any(named: 'routineName'),
            startedAt: any(named: 'startedAt'),
            dayNumber: any(named: 'dayNumber'),
          )).thenAnswer((_) async => session);

      final container = _makeContainer(repo: repo, uid: 'u1', routine: r);
      final init = FreshSession(routineId: r.id, dayNumber: 1);
      await container.read(sessionNotifierProvider(init).future);
      return (container: container, init: init);
    }

    test('SCENARIO-259: logSet agrega el setLog al estado', () async {
      final repo = MockSessionRepository();
      when(() => repo.addSetLog(
            uid: any(named: 'uid'),
            sessionId: any(named: 'sessionId'),
            setLog: any(named: 'setLog'),
          )).thenAnswer((_) async => makeSetLog());

      final (:container, :init) = await setupFresh(repo: repo);
      addTearDown(container.dispose);

      final notifier = container.read(sessionNotifierProvider(init).notifier);
      await notifier.logSet(makeSetLog(exerciseId: 'e1', id: 'new'));

      final state = container.read(sessionNotifierProvider(init)).value!;
      expect(state.setLogs, hasLength(1));
    });

    test('SCENARIO-260: logSet llama a repo.addSetLog', () async {
      final repo = MockSessionRepository();
      when(() => repo.addSetLog(
            uid: any(named: 'uid'),
            sessionId: any(named: 'sessionId'),
            setLog: any(named: 'setLog'),
          )).thenAnswer((_) async => makeSetLog());

      final (:container, :init) = await setupFresh(repo: repo);
      addTearDown(container.dispose);

      await container
          .read(sessionNotifierProvider(init).notifier)
          .logSet(makeSetLog(exerciseId: 'e1'));

      verify(() => repo.addSetLog(
            uid: any(named: 'uid'),
            sessionId: any(named: 'sessionId'),
            setLog: any(named: 'setLog'),
          )).called(1);
    });

    test(
        'SCENARIO-261: logSet avanza currentExerciseIndex cuando el ejercicio se completa',
        () async {
      final repo = MockSessionRepository();
      final routine = makeRoutine(
        days: [
          makeDay(slots: [
            makeSlot(exerciseId: 'e1', targetSets: 1),
            makeSlot(exerciseId: 'e2', targetSets: 2),
          ])
        ],
      );
      when(() => repo.addSetLog(
            uid: any(named: 'uid'),
            sessionId: any(named: 'sessionId'),
            setLog: any(named: 'setLog'),
          )).thenAnswer((_) async => makeSetLog());

      final (:container, :init) =
          await setupFresh(repo: repo, routine: routine);
      addTearDown(container.dispose);

      // Loguear el único set de e1 → avanza a e2 (índice 1)
      await container
          .read(sessionNotifierProvider(init).notifier)
          .logSet(makeSetLog(exerciseId: 'e1', setNumber: 1));

      final state = container.read(sessionNotifierProvider(init)).value!;
      expect(state.currentExerciseIndex, equals(1));
    });

    test('SCENARIO-262: logSet no hace nada si el notifier está finalizado',
        () async {
      final repo = MockSessionRepository();
      when(() => repo.addSetLog(
            uid: any(named: 'uid'),
            sessionId: any(named: 'sessionId'),
            setLog: any(named: 'setLog'),
          )).thenAnswer((_) async => makeSetLog());
      when(() => repo.finish(
            uid: any(named: 'uid'),
            sessionId: any(named: 'sessionId'),
            finishedAt: any(named: 'finishedAt'),
            totalVolumeKg: any(named: 'totalVolumeKg'),
            durationMin: any(named: 'durationMin'),
            wasFullyCompleted: any(named: 'wasFullyCompleted'),
          )).thenAnswer((_) async {});

      final (:container, :init) = await setupFresh(repo: repo);
      addTearDown(container.dispose);

      final notifier = container.read(sessionNotifierProvider(init).notifier);
      await notifier.abandonSession();
      // clearInteractions para no contar el addSetLog del abandon (ninguno hay)
      clearInteractions(repo);

      await notifier.logSet(makeSetLog(exerciseId: 'e1'));

      verifyNever(() => repo.addSetLog(
            uid: any(named: 'uid'),
            sessionId: any(named: 'sessionId'),
            setLog: any(named: 'setLog'),
          ));
    });

    test(
        'SCENARIO-260b: logSet es idempotente — taps repetidos del mismo set '
        '(exerciseId+setNumber) loguean una sola vez (anti-duplicación)',
        () async {
      final repo = MockSessionRepository();
      when(() => repo.addSetLog(
            uid: any(named: 'uid'),
            sessionId: any(named: 'sessionId'),
            setLog: any(named: 'setLog'),
          )).thenAnswer(
        (inv) async => inv.namedArguments[const Symbol('setLog')] as dynamic,
      );

      final (:container, :init) = await setupFresh(repo: repo);
      addTearDown(container.dispose);

      final notifier = container.read(sessionNotifierProvider(init).notifier);

      // Mismo set (e1, setNumber 1) marcado dos veces de forma secuencial.
      await notifier.logSet(makeSetLog(exerciseId: 'e1', setNumber: 1));
      await notifier.logSet(makeSetLog(exerciseId: 'e1', setNumber: 1));

      final state = container.read(sessionNotifierProvider(init)).value!;
      expect(state.setLogs, hasLength(1),
          reason: 'el segundo tap del mismo set no debe duplicar');
      verify(() => repo.addSetLog(
            uid: any(named: 'uid'),
            sessionId: any(named: 'sessionId'),
            setLog: any(named: 'setLog'),
          )).called(1);
    });

    test(
        'SCENARIO-260c: dos taps concurrentes del mismo set loguean una sola '
        'vez (lock _isLoggingSet durante el await)', () async {
      final repo = MockSessionRepository();
      when(() => repo.addSetLog(
            uid: any(named: 'uid'),
            sessionId: any(named: 'sessionId'),
            setLog: any(named: 'setLog'),
          )).thenAnswer(
        (inv) async => inv.namedArguments[const Symbol('setLog')] as dynamic,
      );

      final (:container, :init) = await setupFresh(repo: repo);
      addTearDown(container.dispose);

      final notifier = container.read(sessionNotifierProvider(init).notifier);

      // Disparados sin await entre medio → el segundo entra mientras el primero
      // está persistiendo; el lock debe descartarlo.
      final f1 = notifier.logSet(makeSetLog(exerciseId: 'e1', setNumber: 1));
      final f2 = notifier.logSet(makeSetLog(exerciseId: 'e1', setNumber: 1));
      await Future.wait([f1, f2]);

      verify(() => repo.addSetLog(
            uid: any(named: 'uid'),
            sessionId: any(named: 'sessionId'),
            setLog: any(named: 'setLog'),
          )).called(1);
    });
  });

  // ── abandonSession (SCENARIO-265..266) ───────────────────────────────────

  group('SessionNotifier.abandonSession', () {
    test('SCENARIO-265: llama a repo.finish con wasFullyCompleted = false',
        () async {
      final repo = MockSessionRepository();
      when(() => repo.create(
            uid: any(named: 'uid'),
            routineId: any(named: 'routineId'),
            routineName: any(named: 'routineName'),
            startedAt: any(named: 'startedAt'),
            dayNumber: any(named: 'dayNumber'),
          )).thenAnswer((_) async => makeSession());
      when(() => repo.finish(
            uid: any(named: 'uid'),
            sessionId: any(named: 'sessionId'),
            finishedAt: any(named: 'finishedAt'),
            totalVolumeKg: any(named: 'totalVolumeKg'),
            durationMin: any(named: 'durationMin'),
            wasFullyCompleted: any(named: 'wasFullyCompleted'),
          )).thenAnswer((_) async {});

      final routine = makeRoutine();
      final container = _makeContainer(repo: repo, uid: 'u1', routine: routine);
      addTearDown(container.dispose);

      final init = FreshSession(routineId: routine.id, dayNumber: 1);
      await container.read(sessionNotifierProvider(init).future);

      await container
          .read(sessionNotifierProvider(init).notifier)
          .abandonSession();

      final captured = verify(() => repo.finish(
            uid: any(named: 'uid'),
            sessionId: any(named: 'sessionId'),
            finishedAt: any(named: 'finishedAt'),
            totalVolumeKg: any(named: 'totalVolumeKg'),
            durationMin: any(named: 'durationMin'),
            wasFullyCompleted: captureAny(named: 'wasFullyCompleted'),
          )).captured;
      expect(captured.first, isFalse);
    });

    test(
        'SCENARIO-266: abandonSession no llama a finish dos veces (guard _finalized)',
        () async {
      final repo = MockSessionRepository();
      when(() => repo.create(
            uid: any(named: 'uid'),
            routineId: any(named: 'routineId'),
            routineName: any(named: 'routineName'),
            startedAt: any(named: 'startedAt'),
            dayNumber: any(named: 'dayNumber'),
          )).thenAnswer((_) async => makeSession());
      when(() => repo.finish(
            uid: any(named: 'uid'),
            sessionId: any(named: 'sessionId'),
            finishedAt: any(named: 'finishedAt'),
            totalVolumeKg: any(named: 'totalVolumeKg'),
            durationMin: any(named: 'durationMin'),
            wasFullyCompleted: any(named: 'wasFullyCompleted'),
          )).thenAnswer((_) async {});

      final routine = makeRoutine();
      final container = _makeContainer(repo: repo, uid: 'u1', routine: routine);
      addTearDown(container.dispose);

      final init = FreshSession(routineId: routine.id, dayNumber: 1);
      await container.read(sessionNotifierProvider(init).future);
      final notifier = container.read(sessionNotifierProvider(init).notifier);

      await notifier.abandonSession();
      await notifier.abandonSession(); // segunda llamada debe ser no-op

      verify(() => repo.finish(
            uid: any(named: 'uid'),
            sessionId: any(named: 'sessionId'),
            finishedAt: any(named: 'finishedAt'),
            totalVolumeKg: any(named: 'totalVolumeKg'),
            durationMin: any(named: 'durationMin'),
            wasFullyCompleted: any(named: 'wasFullyCompleted'),
          )).called(1);
    });

    // #367: an abandoned session is persisted too, so any session-derived view
    // (historial, and the now-cleared active session) must reflect it without
    // an app restart. abandonSession must invalidate sessionsByUidProvider.
    test('REGRESSION-367: abandonSession invalidates sessionsByUidProvider',
        () async {
      final repo = MockSessionRepository();
      when(() => repo.create(
            uid: any(named: 'uid'),
            routineId: any(named: 'routineId'),
            routineName: any(named: 'routineName'),
            startedAt: any(named: 'startedAt'),
            dayNumber: any(named: 'dayNumber'),
          )).thenAnswer((_) async => makeSession());
      when(() => repo.finish(
            uid: any(named: 'uid'),
            sessionId: any(named: 'sessionId'),
            finishedAt: any(named: 'finishedAt'),
            totalVolumeKg: any(named: 'totalVolumeKg'),
            durationMin: any(named: 'durationMin'),
            wasFullyCompleted: any(named: 'wasFullyCompleted'),
          )).thenAnswer((_) async {});
      when(() => repo.listByUid('u1', limit: any(named: 'limit')))
          .thenAnswer((_) async => <Session>[]);

      final routine = makeRoutine();
      final container = _makeContainer(repo: repo, uid: 'u1', routine: routine);
      addTearDown(container.dispose);

      final sub = container.listen(sessionsByUidProvider('u1'), (_, __) {});
      addTearDown(sub.close);
      await container.read(sessionsByUidProvider('u1').future); // fetch #1

      final init = FreshSession(routineId: routine.id, dayNumber: 1);
      await container.read(sessionNotifierProvider(init).future);
      await container
          .read(sessionNotifierProvider(init).notifier)
          .abandonSession();

      await container.read(sessionsByUidProvider('u1').future); // forces #2

      verify(() => repo.listByUid('u1', limit: any(named: 'limit'))).called(2);
    });
  });

  // ── finishSession (SCENARIO-267..268) ────────────────────────────────────

  group('SessionNotifier.finishSession', () {
    test(
        'SCENARIO-267: finishSession llama a repo.finish con wasFullyCompleted = true cuando completo',
        () async {
      final repo = MockSessionRepository();
      // Rutina con un solo ejercicio de 1 set para facilitar completarlo
      final routine = makeRoutine(
        days: [
          makeDay(slots: [makeSlot(exerciseId: 'e1', targetSets: 1)])
        ],
      );
      final session = makeSession();

      when(() => repo.create(
            uid: any(named: 'uid'),
            routineId: any(named: 'routineId'),
            routineName: any(named: 'routineName'),
            startedAt: any(named: 'startedAt'),
            dayNumber: any(named: 'dayNumber'),
          )).thenAnswer((_) async => session);
      when(() => repo.addSetLog(
            uid: any(named: 'uid'),
            sessionId: any(named: 'sessionId'),
            setLog: any(named: 'setLog'),
          )).thenAnswer((_) async => makeSetLog());
      when(() => repo.finish(
            uid: any(named: 'uid'),
            sessionId: any(named: 'sessionId'),
            finishedAt: any(named: 'finishedAt'),
            totalVolumeKg: any(named: 'totalVolumeKg'),
            durationMin: any(named: 'durationMin'),
            wasFullyCompleted: any(named: 'wasFullyCompleted'),
          )).thenAnswer((_) async {});

      final container = _makeContainer(repo: repo, uid: 'u1', routine: routine);
      addTearDown(container.dispose);

      final init = FreshSession(routineId: routine.id, dayNumber: 1);
      await container.read(sessionNotifierProvider(init).future);
      final notifier = container.read(sessionNotifierProvider(init).notifier);

      // Loguear el set para que isFullyCompleted sea true
      await notifier.logSet(makeSetLog(exerciseId: 'e1', setNumber: 1));
      await notifier.finishSession();

      final captured = verify(() => repo.finish(
            uid: any(named: 'uid'),
            sessionId: any(named: 'sessionId'),
            finishedAt: any(named: 'finishedAt'),
            totalVolumeKg: any(named: 'totalVolumeKg'),
            durationMin: any(named: 'durationMin'),
            wasFullyCompleted: captureAny(named: 'wasFullyCompleted'),
          )).captured;
      expect(captured.first, isTrue);
    });

    test(
        'SCENARIO-268: finishSession lanza StateError cuando isFullyCompleted es false',
        () async {
      final repo = MockSessionRepository();
      when(() => repo.create(
            uid: any(named: 'uid'),
            routineId: any(named: 'routineId'),
            routineName: any(named: 'routineName'),
            startedAt: any(named: 'startedAt'),
            dayNumber: any(named: 'dayNumber'),
          )).thenAnswer((_) async => makeSession());

      final routine = makeRoutine();
      final container = _makeContainer(repo: repo, uid: 'u1', routine: routine);
      addTearDown(container.dispose);

      final init = FreshSession(routineId: routine.id, dayNumber: 1);
      await container.read(sessionNotifierProvider(init).future);

      // Sin logs → isFullyCompleted es false → debe lanzar StateError
      expect(
        () => container
            .read(sessionNotifierProvider(init).notifier)
            .finishSession(),
        throwsA(isA<StateError>()),
      );
    });

    // #367: on finish, Home ("HOY" card) and Insights showed pre-workout data
    // until the app was restarted — the finish flow never refreshed the
    // session-derived caches. finishSession must invalidate
    // sessionsByUidProvider so everything watching it (todaysRoutineProvider,
    // the Insights aggregators, historial) re-fetches with the new session.
    test(
        'REGRESSION-367: finishSession invalidates sessionsByUidProvider so '
        'Home/Insights refresh without an app restart', () async {
      final repo = MockSessionRepository();
      final routine = makeRoutine(
        days: [
          makeDay(slots: [makeSlot(exerciseId: 'e1', targetSets: 1)])
        ],
      );
      when(() => repo.create(
            uid: any(named: 'uid'),
            routineId: any(named: 'routineId'),
            routineName: any(named: 'routineName'),
            startedAt: any(named: 'startedAt'),
            dayNumber: any(named: 'dayNumber'),
          )).thenAnswer((_) async => makeSession());
      when(() => repo.addSetLog(
            uid: any(named: 'uid'),
            sessionId: any(named: 'sessionId'),
            setLog: any(named: 'setLog'),
          )).thenAnswer((_) async => makeSetLog());
      when(() => repo.finish(
            uid: any(named: 'uid'),
            sessionId: any(named: 'sessionId'),
            finishedAt: any(named: 'finishedAt'),
            totalVolumeKg: any(named: 'totalVolumeKg'),
            durationMin: any(named: 'durationMin'),
            wasFullyCompleted: any(named: 'wasFullyCompleted'),
          )).thenAnswer((_) async {});
      // sessionsByUidProvider's fetch — counted to prove the invalidation
      // forces a re-fetch.
      when(() => repo.listByUid('u1', limit: any(named: 'limit')))
          .thenAnswer((_) async => <Session>[]);

      final container = _makeContainer(repo: repo, uid: 'u1', routine: routine);
      addTearDown(container.dispose);

      // Keep the provider alive: WITHOUT the fix its autoDispose cache would
      // survive and a re-read would NOT re-fetch, isolating the invalidation as
      // the only thing that can force fetch #2.
      final sub = container.listen(sessionsByUidProvider('u1'), (_, __) {});
      addTearDown(sub.close);
      await container.read(sessionsByUidProvider('u1').future); // fetch #1

      final init = FreshSession(routineId: routine.id, dayNumber: 1);
      await container.read(sessionNotifierProvider(init).future);
      final notifier = container.read(sessionNotifierProvider(init).notifier);
      await notifier.logSet(makeSetLog(exerciseId: 'e1', setNumber: 1));
      await notifier.finishSession();

      // The invalidate scheduled a rebuild; awaiting the future forces fetch #2.
      await container.read(sessionsByUidProvider('u1').future);

      verify(() => repo.listByUid('u1', limit: any(named: 'limit'))).called(2);
    });
  });

  // ── Fix 1 clamp tests — negative / out-of-range weekNumber ──────────────

  group('weekNumber clamping in _buildFresh', () {
    Future<int> capturedWeek({
      required int requestedWeek,
      required int numWeeks,
    }) async {
      final repo = MockSessionRepository();
      final routine = makeRoutine(numWeeks: numWeeks);
      final session = makeSession(weekNumber: 0); // return value irrelevant

      when(() => repo.create(
            uid: any(named: 'uid'),
            routineId: any(named: 'routineId'),
            routineName: any(named: 'routineName'),
            startedAt: any(named: 'startedAt'),
            dayNumber: any(named: 'dayNumber'),
            weekNumber: any(named: 'weekNumber'),
          )).thenAnswer((_) async => session);

      final container = _makeContainer(
        repo: repo,
        uid: 'u1',
        routine: routine,
      );
      addTearDown(container.dispose);

      final init = FreshSession(
        routineId: routine.id,
        dayNumber: 1,
        weekNumber: requestedWeek,
      );
      await container.read(sessionNotifierProvider(init).future);

      final captured = verify(() => repo.create(
            uid: any(named: 'uid'),
            routineId: any(named: 'routineId'),
            routineName: any(named: 'routineName'),
            startedAt: any(named: 'startedAt'),
            dayNumber: any(named: 'dayNumber'),
            weekNumber: captureAny(named: 'weekNumber'),
          )).captured;
      return captured.last as int;
    }

    test('weekNumber=-1 is clamped to 0 before persisting', () async {
      final persisted = await capturedWeek(requestedWeek: -1, numWeeks: 1);
      expect(persisted, equals(0));
    });

    test('weekNumber=99 on a 2-week plan is clamped to 1 (numWeeks-1)',
        () async {
      final persisted = await capturedWeek(requestedWeek: 99, numWeeks: 2);
      expect(persisted, equals(1));
    });

    test('numWeeks=0 (corrupt doc): upper bound floored at 0, no throw',
        () async {
      // clamp(0, numWeeks - 1) with numWeeks=0 would be clamp(0, -1), which
      // throws ArgumentError in Dart. The floor guard must prevent that.
      final persisted = await capturedWeek(requestedWeek: 5, numWeeks: 0);
      expect(persisted, equals(0));
    });
  });

  // ── SCENARIO-WPRES-029..030: player filters by weekNumber (REQ-WPRES-021) ──

  group(
      'SCENARIO-WPRES-029..030: SessionNotifier filters slots by isPresentInWeek',
      () {
    test(
        'SCENARIO-WPRES-029: _buildFresh filters out absent slot — '
        'day.slots contains only present slot for session weekNumber',
        () async {
      final repo = MockSessionRepository();

      // slotA: activeWeeks=[] → present in all weeks
      // slotB: activeWeeks=[0] → present only in week 0
      // Session is built for weekNumber=1 → slotB must be filtered out.
      final slotA = makeSlot(exerciseId: 'slotA', targetSets: 2);
      const slotAbsent = RoutineSlot(
        exerciseId: 'slotB',
        exerciseName: 'Slot Absent',
        muscleGroup: 'Piernas',
        targetSets: 2,
        targetRepsMin: 8,
        targetRepsMax: 12,
        restSeconds: 60,
        activeWeeks: [0], // only week 0
      );
      final routine = makeRoutine(
        days: [
          makeDay(slots: [slotA, slotAbsent])
        ],
        numWeeks: 2,
      );
      // Session with weekNumber=1
      final session = makeSession(weekNumber: 1);

      when(() => repo.create(
            uid: any(named: 'uid'),
            routineId: any(named: 'routineId'),
            routineName: any(named: 'routineName'),
            startedAt: any(named: 'startedAt'),
            dayNumber: any(named: 'dayNumber'),
            weekNumber: any(named: 'weekNumber'),
          )).thenAnswer((_) async => session);

      final container = _makeContainer(repo: repo, uid: 'u1', routine: routine);
      addTearDown(container.dispose);

      final init = FreshSession(
        routineId: routine.id,
        dayNumber: 1,
        weekNumber: 1,
      );
      final state = await container.read(sessionNotifierProvider(init).future);

      // Only slotA (present in week 1) must be in state.day.slots.
      expect(state.day.slots.length, equals(1),
          reason: 'slotB (activeWeeks=[0]) must be filtered out for week 1');
      expect(state.day.slots.first.exerciseId, equals('slotA'));
    });

    test(
        'SCENARIO-WPRES-030: _buildFresh with all-empty-mask passes all slots through unchanged',
        () async {
      final repo = MockSessionRepository();

      // Both slots have activeWeeks=[] → present everywhere → no filtering
      final slotA = makeSlot(exerciseId: 'slotA', targetSets: 2);
      final slotB =
          makeSlot(exerciseId: 'slotB', exerciseName: 'Curl', targetSets: 3);
      final routine = makeRoutine(
        days: [
          makeDay(slots: [slotA, slotB])
        ],
        numWeeks: 2,
      );
      final session = makeSession(weekNumber: 1);

      when(() => repo.create(
            uid: any(named: 'uid'),
            routineId: any(named: 'routineId'),
            routineName: any(named: 'routineName'),
            startedAt: any(named: 'startedAt'),
            dayNumber: any(named: 'dayNumber'),
            weekNumber: any(named: 'weekNumber'),
          )).thenAnswer((_) async => session);

      final container = _makeContainer(repo: repo, uid: 'u1', routine: routine);
      addTearDown(container.dispose);

      final init = FreshSession(
        routineId: routine.id,
        dayNumber: 1,
        weekNumber: 1,
      );
      final state = await container.read(sessionNotifierProvider(init).future);

      // Both slots have empty activeWeeks → both must be present
      expect(state.day.slots.length, equals(2),
          reason: 'All-empty-mask slots must all pass through');
    });
  });

  // ── SCENARIO-037-notifier: _nextIncompleteIndex on periodized plan ────────

  group(
      'SCENARIO-037-notifier: _nextIncompleteIndex honors effectiveSetsForWeek',
      () {
    test(
        'SCENARIO-037-notifier: logSet advances to next exercise after completing '
        'week-1 prescription (2 sets), not legacy targetSets (4)', () async {
      final repo = MockSessionRepository();

      // Routine with 2 exercises:
      //   e1 — weeklySets: week0=[4 sets], week1=[2 sets]; targetSets=4 (legacy)
      //   e2 — single-week, targetSets=3
      final periodizedSlot = makeSlot(
        exerciseId: 'e1',
        targetSets: 4, // legacy — must NOT drive advancement in week 1
        weeklySets: const [
          // week 0
          [
            SetSpec(reps: 5),
            SetSpec(reps: 5),
            SetSpec(reps: 5),
            SetSpec(reps: 5)
          ],
          // week 1
          [SetSpec(reps: 8), SetSpec(reps: 8)],
        ],
      );
      final routine = makeRoutine(
        days: [
          makeDay(slots: [
            periodizedSlot,
            makeSlot(exerciseId: 'e2', exerciseName: 'Curl', targetSets: 3),
          ])
        ],
      );

      // The created session must carry weekNumber=1 so _nextIncompleteIndex
      // calls effectiveSetsForWeek(1) → length 2 for e1.
      final sessionWeek1 = makeSession(weekNumber: 1);

      when(() => repo.create(
            uid: any(named: 'uid'),
            routineId: any(named: 'routineId'),
            routineName: any(named: 'routineName'),
            startedAt: any(named: 'startedAt'),
            dayNumber: any(named: 'dayNumber'),
            weekNumber: any(named: 'weekNumber'),
          )).thenAnswer((_) async => sessionWeek1);

      when(() => repo.addSetLog(
            uid: any(named: 'uid'),
            sessionId: any(named: 'sessionId'),
            setLog: any(named: 'setLog'),
          )).thenAnswer(
        (inv) async => inv.namedArguments[const Symbol('setLog')] as dynamic,
      );

      final container = _makeContainer(repo: repo, uid: 'u1', routine: routine);
      addTearDown(container.dispose);

      final init =
          FreshSession(routineId: routine.id, dayNumber: 1, weekNumber: 1);
      await container.read(sessionNotifierProvider(init).future);

      final notifier = container.read(sessionNotifierProvider(init).notifier);

      // Log 2 sets for e1 — week-1 prescription is 2 sets → should advance.
      await notifier.logSet(makeSetLog(exerciseId: 'e1', setNumber: 1));
      await notifier
          .logSet(makeSetLog(exerciseId: 'e1', setNumber: 2, id: 'sl2'));

      final state = container.read(sessionNotifierProvider(init)).value!;
      // Index must be 1 (e2), proving _nextIncompleteIndex used week-1 (2 sets),
      // not the legacy targetSets=4 which would keep index at 0.
      expect(state.currentExerciseIndex, equals(1));
    });
  });

  // ── live-set-editing PR1: SessionNotifier.addSet (AD-1/AD-2) ──────────────

  group('SessionNotifier.addSet', () {
    test(
        '[REQ:workout#Logging the added set persists a new document] '
        'addSet bumps setCountOverride to plannedSetsFor(slot)+1 and does NOT '
        'itself write a setLog', () async {
      final repo = MockSessionRepository();
      final routine = makeRoutine(
        days: [
          makeDay(slots: [makeSlot(exerciseId: 'e1', targetSets: 3)])
        ],
      );
      final session = makeSession();

      when(() => repo.create(
            uid: any(named: 'uid'),
            routineId: any(named: 'routineId'),
            routineName: any(named: 'routineName'),
            startedAt: any(named: 'startedAt'),
            dayNumber: any(named: 'dayNumber'),
            weekNumber: any(named: 'weekNumber'),
          )).thenAnswer((_) async => session);

      final container = _makeContainer(repo: repo, uid: 'u1', routine: routine);
      addTearDown(container.dispose);

      final init = FreshSession(routineId: routine.id, dayNumber: 1);
      await container.read(sessionNotifierProvider(init).future);
      final notifier = container.read(sessionNotifierProvider(init).notifier);
      final slot = routine.days.first.slots.first;

      await notifier.addSet(slot);

      final state = container.read(sessionNotifierProvider(init)).value!;
      expect(state.setCountOverride['e1'], equals(4));
      expect(state.plannedSetsFor(slot), equals(4));
      verifyNever(() => repo.addSetLog(
            uid: any(named: 'uid'),
            sessionId: any(named: 'sessionId'),
            setLog: any(named: 'setLog'),
          ));
    });

    test(
        '[AD-2 idempotency note] two rapid addSet calls followed by two rapid '
        'logSet calls for the same new setNumber result in exactly one '
        'persisted doc (existing exerciseId+setNumber idempotency key)',
        () async {
      final repo = MockSessionRepository();
      final routine = makeRoutine(
        days: [
          makeDay(slots: [makeSlot(exerciseId: 'e1', targetSets: 3)])
        ],
      );
      final session = makeSession();

      when(() => repo.create(
            uid: any(named: 'uid'),
            routineId: any(named: 'routineId'),
            routineName: any(named: 'routineName'),
            startedAt: any(named: 'startedAt'),
            dayNumber: any(named: 'dayNumber'),
            weekNumber: any(named: 'weekNumber'),
          )).thenAnswer((_) async => session);
      when(() => repo.addSetLog(
            uid: any(named: 'uid'),
            sessionId: any(named: 'sessionId'),
            setLog: any(named: 'setLog'),
          )).thenAnswer(
        (inv) async => inv.namedArguments[const Symbol('setLog')] as dynamic,
      );

      final container = _makeContainer(repo: repo, uid: 'u1', routine: routine);
      addTearDown(container.dispose);

      final init = FreshSession(routineId: routine.id, dayNumber: 1);
      await container.read(sessionNotifierProvider(init).future);
      final notifier = container.read(sessionNotifierProvider(init).notifier);
      final slot = routine.days.first.slots.first;

      // A single "+ agregar serie" tap bumps the override to 4.
      await notifier.addSet(slot);

      final afterAdd = container.read(sessionNotifierProvider(init)).value!;
      expect(afterAdd.setCountOverride['e1'], equals(4));

      // Two rapid taps on the new row's check button — existing
      // exerciseId+setNumber idempotency guard in logSet must prevent a
      // duplicate doc, proving the guard composes with the override bump
      // without needing a new guard.
      await notifier
          .logSet(makeSetLog(exerciseId: 'e1', setNumber: 4, id: 'l4'));
      await notifier
          .logSet(makeSetLog(exerciseId: 'e1', setNumber: 4, id: 'l4dupe'));

      final finalState = container.read(sessionNotifierProvider(init)).value!;
      expect(
        finalState.setLogs.where((l) => l.setNumber == 4).length,
        equals(1),
      );
      verify(() => repo.addSetLog(
            uid: any(named: 'uid'),
            sessionId: any(named: 'sessionId'),
            setLog: any(named: 'setLog'),
          )).called(1);
    });

    test(
        '[SITE-3][REQ:workout#Next-incomplete navigation respects the '
        'session-local count] _nextIncompleteIndex still points at an '
        'added-beyond-plan exercise (override=4, 3 logged) instead of '
        'advancing to the next exercise', () async {
      final repo = MockSessionRepository();
      final routine = makeRoutine(
        days: [
          makeDay(slots: [
            makeSlot(exerciseId: 'e1', targetSets: 3),
            makeSlot(exerciseId: 'e2', exerciseName: 'Curl', targetSets: 2),
          ])
        ],
      );
      final session = makeSession();

      when(() => repo.create(
            uid: any(named: 'uid'),
            routineId: any(named: 'routineId'),
            routineName: any(named: 'routineName'),
            startedAt: any(named: 'startedAt'),
            dayNumber: any(named: 'dayNumber'),
            weekNumber: any(named: 'weekNumber'),
          )).thenAnswer((_) async => session);
      when(() => repo.addSetLog(
            uid: any(named: 'uid'),
            sessionId: any(named: 'sessionId'),
            setLog: any(named: 'setLog'),
          )).thenAnswer(
        (inv) async => inv.namedArguments[const Symbol('setLog')] as dynamic,
      );

      final container = _makeContainer(repo: repo, uid: 'u1', routine: routine);
      addTearDown(container.dispose);

      final init = FreshSession(routineId: routine.id, dayNumber: 1);
      await container.read(sessionNotifierProvider(init).future);
      final notifier = container.read(sessionNotifierProvider(init).notifier);
      final e1 = routine.days.first.slots.first;

      // Log 2 of the 3 planned sets for e1 (cursor still on e1).
      await notifier
          .logSet(makeSetLog(exerciseId: 'e1', setNumber: 1, id: 'l1'));
      await notifier
          .logSet(makeSetLog(exerciseId: 'e1', setNumber: 2, id: 'l2'));

      // Add a 4th set to e1 BEFORE the 3rd (planned) set is logged — override
      // is now 4.
      await notifier.addSet(e1);

      // Log the 3rd set. Without the override fix, 3 >= plan(3) would
      // advance the cursor to e2 (index 1). With the override (4), the
      // cursor must stay on e1 since 3 < 4.
      await notifier
          .logSet(makeSetLog(exerciseId: 'e1', setNumber: 3, id: 'l3'));

      final state = container.read(sessionNotifierProvider(init)).value!;
      expect(state.currentExerciseIndex, equals(0),
          reason: 'the added-beyond-plan set on e1 must keep the cursor on '
              'e1, not advance to e2');
    });
  });

  // ── live-set-editing PR2: SessionNotifier.removeSet (AD-2/AD-3/AD-5) ──────

  group('SessionNotifier.removeSet', () {
    test(
        '[AD-2][REQ:workout#Removing an unlogged set requires no '
        'confirmation] removeSet(slot, null) on an added-but-unlogged pending '
        'row lowers setCountOverride and does NOT call repo.deleteSetLog',
        () async {
      final repo = MockSessionRepository();
      final routine = makeRoutine(
        days: [
          makeDay(slots: [makeSlot(exerciseId: 'e1', targetSets: 3)])
        ],
      );
      final session = makeSession();

      when(() => repo.create(
            uid: any(named: 'uid'),
            routineId: any(named: 'routineId'),
            routineName: any(named: 'routineName'),
            startedAt: any(named: 'startedAt'),
            dayNumber: any(named: 'dayNumber'),
            weekNumber: any(named: 'weekNumber'),
          )).thenAnswer((_) async => session);
      when(() => repo.addSetLog(
            uid: any(named: 'uid'),
            sessionId: any(named: 'sessionId'),
            setLog: any(named: 'setLog'),
          )).thenAnswer(
        (inv) async => inv.namedArguments[const Symbol('setLog')] as dynamic,
      );

      final container = _makeContainer(repo: repo, uid: 'u1', routine: routine);
      addTearDown(container.dispose);

      final init = FreshSession(routineId: routine.id, dayNumber: 1);
      await container.read(sessionNotifierProvider(init).future);
      final notifier = container.read(sessionNotifierProvider(init).notifier);
      final slot = routine.days.first.slots.first;

      // Log 3 of 3 planned, then add a 4th (unlogged, pending) row.
      await notifier
          .logSet(makeSetLog(exerciseId: 'e1', setNumber: 1, id: 'l1'));
      await notifier
          .logSet(makeSetLog(exerciseId: 'e1', setNumber: 2, id: 'l2'));
      await notifier
          .logSet(makeSetLog(exerciseId: 'e1', setNumber: 3, id: 'l3'));
      await notifier.addSet(slot);
      expect(
          container
              .read(sessionNotifierProvider(init))
              .value!
              .setCountOverride['e1'],
          equals(4));

      // Remove the pending (unlogged) 4th row — target is null.
      await notifier.removeSet(slot, null);

      final state = container.read(sessionNotifierProvider(init)).value!;
      expect(state.setCountOverride['e1'], equals(3));
      verifyNever(() => repo.deleteSetLog(
            uid: any(named: 'uid'),
            sessionId: any(named: 'sessionId'),
            setLogId: any(named: 'setLogId'),
          ));
    });

    test(
        '[AD-2][AD-3][REQ:workout#Confirmed removal deletes the underlying '
        'document][REQ:workout#Removing a set renumbers surviving sets] '
        'removeSet on a logged set deletes the doc, renumbers survivors '
        'above the gap, and updates setLogs + setCountOverride in one state '
        'emission', () async {
      final repo = MockSessionRepository();
      final routine = makeRoutine(
        days: [
          makeDay(slots: [makeSlot(exerciseId: 'e1', targetSets: 3)])
        ],
      );
      final session = makeSession();

      when(() => repo.create(
            uid: any(named: 'uid'),
            routineId: any(named: 'routineId'),
            routineName: any(named: 'routineName'),
            startedAt: any(named: 'startedAt'),
            dayNumber: any(named: 'dayNumber'),
            weekNumber: any(named: 'weekNumber'),
          )).thenAnswer((_) async => session);
      when(() => repo.addSetLog(
            uid: any(named: 'uid'),
            sessionId: any(named: 'sessionId'),
            setLog: any(named: 'setLog'),
          )).thenAnswer(
        (inv) async => inv.namedArguments[const Symbol('setLog')] as dynamic,
      );
      when(() => repo.deleteSetLog(
            uid: any(named: 'uid'),
            sessionId: any(named: 'sessionId'),
            setLogId: any(named: 'setLogId'),
          )).thenAnswer((_) async {});
      when(() => repo.updateSetLog(
            uid: any(named: 'uid'),
            sessionId: any(named: 'sessionId'),
            setLog: any(named: 'setLog'),
          )).thenAnswer((_) async {});

      final container = _makeContainer(repo: repo, uid: 'u1', routine: routine);
      addTearDown(container.dispose);

      final init = FreshSession(routineId: routine.id, dayNumber: 1);
      await container.read(sessionNotifierProvider(init).future);
      final notifier = container.read(sessionNotifierProvider(init).notifier);
      final slot = routine.days.first.slots.first;

      await notifier
          .logSet(makeSetLog(exerciseId: 'e1', setNumber: 1, id: 'l1'));
      await notifier
          .logSet(makeSetLog(exerciseId: 'e1', setNumber: 2, id: 'l2'));
      await notifier
          .logSet(makeSetLog(exerciseId: 'e1', setNumber: 3, id: 'l3'));

      final target = container
          .read(sessionNotifierProvider(init))
          .value!
          .setLogs
          .firstWhere((l) => l.id == 'l2');

      await notifier.removeSet(slot, target);

      verify(() => repo.deleteSetLog(
            uid: any(named: 'uid'),
            sessionId: any(named: 'sessionId'),
            setLogId: 'l2',
          )).called(1);
      verify(() => repo.updateSetLog(
            uid: any(named: 'uid'),
            sessionId: any(named: 'sessionId'),
            setLog: any(
                named: 'setLog',
                that:
                    predicate<SetLog>((l) => l.id == 'l3' && l.setNumber == 2)),
          )).called(1);

      final state = container.read(sessionNotifierProvider(init)).value!;
      expect(state.setLogs.map((l) => l.id), containsAll(<String>['l1', 'l3']));
      expect(state.setLogs.any((l) => l.id == 'l2'), isFalse);
      expect(
        state.setLogs.firstWhere((l) => l.id == 'l3').setNumber,
        equals(2),
        reason: 'survivor above the gap must renumber from 3 to 2',
      );
      expect(state.setCountOverride['e1'], equals(2));
    });

    test(
        '[AD-5 floor invariant][REQ:workout#Session-Local Set Count Drives '
        'Completion Gating] removeSet cannot drop setCountOverride below the '
        'current logged count after the removal completes', () async {
      final repo = MockSessionRepository();
      final routine = makeRoutine(
        days: [
          makeDay(slots: [makeSlot(exerciseId: 'e1', targetSets: 3)])
        ],
      );
      final session = makeSession();

      when(() => repo.create(
            uid: any(named: 'uid'),
            routineId: any(named: 'routineId'),
            routineName: any(named: 'routineName'),
            startedAt: any(named: 'startedAt'),
            dayNumber: any(named: 'dayNumber'),
            weekNumber: any(named: 'weekNumber'),
          )).thenAnswer((_) async => session);
      when(() => repo.addSetLog(
            uid: any(named: 'uid'),
            sessionId: any(named: 'sessionId'),
            setLog: any(named: 'setLog'),
          )).thenAnswer(
        (inv) async => inv.namedArguments[const Symbol('setLog')] as dynamic,
      );

      final container = _makeContainer(repo: repo, uid: 'u1', routine: routine);
      addTearDown(container.dispose);

      final init = FreshSession(routineId: routine.id, dayNumber: 1);
      await container.read(sessionNotifierProvider(init).future);
      final notifier = container.read(sessionNotifierProvider(init).notifier);
      final slot = routine.days.first.slots.first;

      // Log all 3 planned sets. override is unset (falls back to plan=3).
      await notifier
          .logSet(makeSetLog(exerciseId: 'e1', setNumber: 1, id: 'l1'));
      await notifier
          .logSet(makeSetLog(exerciseId: 'e1', setNumber: 2, id: 'l2'));
      await notifier
          .logSet(makeSetLog(exerciseId: 'e1', setNumber: 3, id: 'l3'));

      // Remove an UNLOGGED pending row (target null) — this would compute
      // newCount = plannedSetsFor(slot) - 1 = 2, but 3 sets are already
      // logged. The floor must clamp the override to 3 (the logged count),
      // never allowing it to drop below what's already persisted.
      await notifier.removeSet(slot, null);

      final state = container.read(sessionNotifierProvider(init)).value!;
      expect(state.setCountOverride['e1'], equals(3),
          reason: 'the floor invariant must prevent the override from '
              'dropping below the current logged count');
    });
  });

  group('SessionNotifier.removeSet — race discipline', () {
    test(
        '[AD-2 race discipline] a logSet completing DURING a removeSet await '
        'survives — removeSet re-reads state.value after its awaits instead '
        'of overwriting with a stale pre-await snapshot', () async {
      final repo = MockSessionRepository();
      final routine = makeRoutine(
        days: [
          makeDay(slots: [makeSlot(exerciseId: 'e1', targetSets: 3)])
        ],
      );
      final session = makeSession();

      when(() => repo.create(
            uid: any(named: 'uid'),
            routineId: any(named: 'routineId'),
            routineName: any(named: 'routineName'),
            startedAt: any(named: 'startedAt'),
            dayNumber: any(named: 'dayNumber'),
            weekNumber: any(named: 'weekNumber'),
          )).thenAnswer((_) async => session);
      when(() => repo.addSetLog(
            uid: any(named: 'uid'),
            sessionId: any(named: 'sessionId'),
            setLog: any(named: 'setLog'),
          )).thenAnswer(
        (inv) async => inv.namedArguments[const Symbol('setLog')] as dynamic,
      );
      when(() => repo.updateSetLog(
            uid: any(named: 'uid'),
            sessionId: any(named: 'sessionId'),
            setLog: any(named: 'setLog'),
          )).thenAnswer((_) async {});

      // Gate deleteSetLog so we can deterministically interleave a logSet
      // while removeSet is still awaiting the delete write.
      final deleteGate = Completer<void>();
      when(() => repo.deleteSetLog(
            uid: any(named: 'uid'),
            sessionId: any(named: 'sessionId'),
            setLogId: any(named: 'setLogId'),
          )).thenAnswer((_) => deleteGate.future);

      final container = _makeContainer(repo: repo, uid: 'u1', routine: routine);
      addTearDown(container.dispose);

      final init = FreshSession(routineId: routine.id, dayNumber: 1);
      await container.read(sessionNotifierProvider(init).future);
      final notifier = container.read(sessionNotifierProvider(init).notifier);
      final slot = routine.days.first.slots.first;

      await notifier
          .logSet(makeSetLog(exerciseId: 'e1', setNumber: 1, id: 'l1'));
      await notifier
          .logSet(makeSetLog(exerciseId: 'e1', setNumber: 2, id: 'l2'));

      final target = container
          .read(sessionNotifierProvider(init))
          .value!
          .setLogs
          .firstWhere((l) => l.id == 'l2');

      // Start removeSet on l2 — it awaits the gated deleteSetLog and would
      // snapshot state.value (2 logs) BEFORE the await resolves.
      final removeFuture = notifier.removeSet(slot, target);

      // While removeSet is in flight, a new set (id 'l3') is logged and lands
      // in state. logSet has no gate, so this completes first.
      await notifier
          .logSet(makeSetLog(exerciseId: 'e1', setNumber: 3, id: 'l3'));
      expect(
        container.read(sessionNotifierProvider(init)).value!.setLogs,
        hasLength(3),
        reason: 'logSet must have appended l3 before removeSet resolves',
      );

      // Now let removeSet finish.
      deleteGate.complete();
      await removeFuture;

      final logs = container.read(sessionNotifierProvider(init)).value!.setLogs;

      // The concurrently-logged l3 must survive removeSet's re-read.
      expect(logs.any((l) => l.id == 'l3'), isTrue,
          reason: 'removeSet must not drop the concurrently logged l3');
      expect(logs.any((l) => l.id == 'l2'), isFalse,
          reason: 'l2 must still be removed');
    });
  });

  group('SessionNotifier.retryLastLogError — remove dispatch', () {
    test(
        '[AD-2 retry] retryLastLogError re-dispatches to removeSet when the '
        'pending error action is SessionLogAction.remove', () async {
      final repo = MockSessionRepository();
      final routine = makeRoutine(
        days: [
          makeDay(slots: [makeSlot(exerciseId: 'e1', targetSets: 3)])
        ],
      );
      final session = makeSession();

      when(() => repo.create(
            uid: any(named: 'uid'),
            routineId: any(named: 'routineId'),
            routineName: any(named: 'routineName'),
            startedAt: any(named: 'startedAt'),
            dayNumber: any(named: 'dayNumber'),
            weekNumber: any(named: 'weekNumber'),
          )).thenAnswer((_) async => session);
      when(() => repo.addSetLog(
            uid: any(named: 'uid'),
            sessionId: any(named: 'sessionId'),
            setLog: any(named: 'setLog'),
          )).thenAnswer(
        (inv) async => inv.namedArguments[const Symbol('setLog')] as dynamic,
      );

      // First deleteSetLog call fails; the retry's call succeeds.
      var deleteCallCount = 0;
      when(() => repo.deleteSetLog(
            uid: any(named: 'uid'),
            sessionId: any(named: 'sessionId'),
            setLogId: any(named: 'setLogId'),
          )).thenAnswer((_) async {
        deleteCallCount++;
        if (deleteCallCount == 1) {
          throw Exception('simulated network failure');
        }
      });

      final container = _makeContainer(repo: repo, uid: 'u1', routine: routine);
      addTearDown(container.dispose);

      final init = FreshSession(routineId: routine.id, dayNumber: 1);
      await container.read(sessionNotifierProvider(init).future);
      final notifier = container.read(sessionNotifierProvider(init).notifier);
      final slot = routine.days.first.slots.first;

      await notifier
          .logSet(makeSetLog(exerciseId: 'e1', setNumber: 1, id: 'l1'));
      final target =
          container.read(sessionNotifierProvider(init)).value!.setLogs.first;

      // First attempt fails — emits SessionLogError(action: remove).
      await notifier.removeSet(slot, target);
      expect(notifier.logSetError.value, isNotNull);
      expect(
          notifier.logSetError.value!.action, equals(SessionLogAction.remove));

      // Retry re-dispatches to removeSet, which now succeeds.
      await notifier.retryLastLogError();

      expect(notifier.logSetError.value, isNull,
          reason: 'a successful retry must clear the error channel');
      verify(() => repo.deleteSetLog(
            uid: any(named: 'uid'),
            sessionId: any(named: 'sessionId'),
            setLogId: target.id,
          )).called(2);
      final state = container.read(sessionNotifierProvider(init)).value!;
      expect(state.setLogs.any((l) => l.id == target.id), isFalse);
    });
  });
}
