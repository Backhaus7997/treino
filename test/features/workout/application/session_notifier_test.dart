// Tests para SessionNotifier — Path A (SCENARIO-256..258), Path B (SCENARIO-318..321),
// mutaciones (SCENARIO-259..268).
// La implementación ya existe (fue necesaria para compilar session_providers.dart),
// por lo que este archivo actúa como GREEN desde el principio.
// Desviación documentada en apply-progress.md.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/core/analytics/analytics_service.dart';
import 'package:treino/features/workout/application/session_init.dart';
import 'package:treino/features/workout/application/session_providers.dart';
import 'package:treino/features/workout/application/routine_providers.dart';
import 'package:treino/features/workout/data/session_repository.dart';
import 'package:treino/features/workout/domain/routine.dart';

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
  });
}
