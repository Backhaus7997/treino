// session_offline_log_test.dart — entrenar sin conexión.
//
// ─── El bug ─────────────────────────────────────────────────────────────────
//
// En Firestore, **un `await` sobre una escritura no resuelve hasta que el
// servidor confirma**. Sin red ese future no completa NUNCA. La escritura sí
// se aplica al cache local de inmediato, y por eso el `.snapshots()` de
// `watchSetLogs` emite igual (compensación de latencia) — pero el `await`
// queda colgado para siempre.
//
// `logSet` tomaba el guard anti doble-tap ANTES de ese `await`:
//
//     _isLoggingSet = true;
//     try   { await repo.addSetLog(...); ... }
//     finally { _isLoggingSet = false; }        // ← nunca corre sin red
//
// Sin conexión, el `try` no sale, el `finally` no corre, y la guarda de la
// primera línea de `logSet` **descarta en silencio todas las series
// siguientes**. Sin error, sin spinner que termine, sin nada.
//
// ─── El síntoma real NO es "no se puede loguear nada" ───────────────────────
//
// Esto importa para entender el bug y para no "arreglarlo" mirando el lugar
// equivocado. La PRIMERA serie **se ve normal**: la escritura entra al cache,
// el stream emite y el estado se actualiza. Es de la SEGUNDA en adelante que
// la pantalla deja de responder, para siempre.
//
// O sea que el atleta no recibe ninguna señal de que algo se rompió. Marca la
// serie 1, la ve tildarse, marca la 2 y no pasa nada. Y no va a pasar nada
// nunca más en esa sesión.
//
// ─── Por qué el test no toca Firestore ──────────────────────────────────────
//
// `fake_cloud_firestore` no modela el offline: sus escrituras resuelven
// siempre, así que ahí el bug es INVISIBLE. Lo que hay que reproducir no es
// Firestore, es "el repositorio no contesta": se cuelga `addSetLog` con un
// Completer, igual que `_gateFinish` en session_notifier_dispose_race_test.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/features/watch/application/watch_credential_providers.dart'
    show watchNudgeServiceProvider;
import 'package:treino/features/watch/data/watch_nudge_service.dart';
import 'package:treino/features/workout/application/routine_providers.dart';
import 'package:treino/features/workout/application/session_init.dart';
import 'package:treino/features/workout/application/session_notifier.dart'
    show SessionLogAction;
import 'package:treino/features/workout/application/session_providers.dart';
import 'package:treino/features/workout/data/session_repository.dart';
import 'package:treino/features/workout/domain/routine.dart';
import 'package:treino/features/workout/domain/set_log.dart';

import 'stub_factories.dart';

/// Anota los avisos que se le mandaron al reloj, con su motivo.
class _SpyWatchNudge implements WatchNudgeService {
  final motivos = <String>[];

  @override
  Future<bool> nudge(
      {String reason = WatchNudgeService.reasonActiveRoutine}) async {
    motivos.add(reason);
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MockSessionRepository extends Mock implements SessionRepository {
  @override
  Stream<List<SetLog>> watchSetLogs({
    required String uid,
    required String sessionId,
  }) =>
      const Stream<List<SetLog>>.empty();

  @override
  Stream<bool> watchSessionFinished({
    required String uid,
    required String sessionId,
  }) =>
      const Stream<bool>.empty();
}

/// Una rutina de un ejercicio con cuatro series, para poder loguear varias.
Routine _fourSetRoutine() => makeRoutine(
      days: [
        makeDay(slots: [makeSlot(exerciseId: 'e1', targetSets: 4)])
      ],
    );

ProviderContainer _makeContainer(
  _MockSessionRepository repo,
  Routine routine,
) {
  return ProviderContainer(
    overrides: [
      sessionRepositoryProvider.overrideWithValue(repo),
      currentUidProvider.overrideWithValue('u1'),
      routineByIdProvider(routine.id).overrideWith((ref) async => routine),
      sessionsByUidProvider('u1').overrideWith((ref) async => const []),
    ],
  );
}

/// Un repositorio EN MODO AVIÓN: contesta el id al instante y no confirma nunca.
///
/// Es el contrato real de Firestore sin red, y el que fija [LoggedSet]:
/// `doc()` genera el id en el cliente —así que `setLog` está disponible sin
/// tocar la red— mientras que el future de `set()` **queda pendiente para
/// siempre**. No falla: queda colgado hasta que vuelve la conexión.
///
/// Por eso `acknowledged` acá es un `Completer` que nadie completa. Si alguien
/// vuelve a meter ese future en el camino crítico de `logSet` —con un `await`,
/// que es exactamente el bug que estos tests cierran— el notifier se cuelga y
/// las aserciones de abajo se ponen rojas.
///
/// Devuelve la lista de series que el notifier alcanzó a mandarle al
/// repositorio, que es lo que el bug perdía en silencio.
List<SetLog> _gateAddSetLog(_MockSessionRepository repo) {
  final recibidas = <SetLog>[];
  when(() => repo.addSetLog(
        uid: any(named: 'uid'),
        sessionId: any(named: 'sessionId'),
        setLog: any(named: 'setLog'),
      )).thenAnswer((inv) {
    final pedida = inv.namedArguments[#setLog] as SetLog;
    recibidas.add(pedida);
    return Future<LoggedSet>.value(
      LoggedSet(
        setLog: pedida.copyWith(
          id: 'doc-${pedida.exerciseId}-${pedida.setNumber}',
        ),
        acknowledged: Completer<void>().future,
      ),
    );
  });
  return recibidas;
}

/// Igual que [_gateAddSetLog] pero devolviendo los `Completer` de cada ACK,
/// para poder simular la vuelta de la red a mano.
List<Completer<void>> _gateAddSetLogConAcks(_MockSessionRepository repo) {
  final acks = <Completer<void>>[];
  when(() => repo.addSetLog(
        uid: any(named: 'uid'),
        sessionId: any(named: 'sessionId'),
        setLog: any(named: 'setLog'),
      )).thenAnswer((inv) {
    final pedida = inv.namedArguments[#setLog] as SetLog;
    final ack = Completer<void>();
    acks.add(ack);
    return Future<LoggedSet>.value(
      LoggedSet(
        setLog: pedida.copyWith(
          id: 'doc-${pedida.exerciseId}-${pedida.setNumber}',
        ),
        acknowledged: ack.future,
      ),
    );
  });
  return acks;
}

void main() {
  setUpAll(() {
    registerFallbackValue(makeSession());
    registerFallbackValue(makeSetLog());
  });

  group('logSet sin conexión', () {
    test(
        'la serie 2 llega al repositorio aunque la 1 siga sin confirmarse '
        '(el guard no se sostiene sobre el ACK del servidor)', () async {
      final repo = _MockSessionRepository();
      final routine = _fourSetRoutine();
      when(() => repo.create(
            uid: any(named: 'uid'),
            routineId: any(named: 'routineId'),
            routineName: any(named: 'routineName'),
            startedAt: any(named: 'startedAt'),
            dayNumber: any(named: 'dayNumber'),
            weekNumber: any(named: 'weekNumber'),
            waitForServer: any(named: 'waitForServer'),
            onServerRejected: any(named: 'onServerRejected'),
          )).thenAnswer((_) async => makeSession());
      final recibidas = _gateAddSetLog(repo);

      final container = _makeContainer(repo, routine);
      addTearDown(container.dispose);

      final init = FreshSession(routineId: routine.id, dayNumber: 1);
      final sub = container.listen(
        sessionNotifierProvider(init),
        (_, __) {},
        fireImmediately: true,
      );
      addTearDown(sub.close);
      await container.read(sessionNotifierProvider(init).future);
      final notifier = container.read(sessionNotifierProvider(init).notifier);

      // OJO: sin `await`. Sin red este future no completa nunca, y esperarlo
      // colgaría el test igual que cuelga a la app — que es justo el punto.
      unawaited(notifier.logSet(makeSetLog(exerciseId: 'e1', setNumber: 1)));
      await Future<void>.delayed(Duration.zero);

      unawaited(notifier.logSet(makeSetLog(exerciseId: 'e1', setNumber: 2)));
      await Future<void>.delayed(Duration.zero);

      unawaited(notifier.logSet(makeSetLog(exerciseId: 'e1', setNumber: 3)));
      await Future<void>.delayed(Duration.zero);

      expect(
        recibidas.map((s) => s.setNumber).toList(),
        [1, 2, 3],
        reason: 'sin conexión, la serie 1 entra al cache y se ve, pero el '
            '`await` sobre su escritura no resuelve nunca. Si el guard anti '
            'doble-tap se sostiene sobre ese await, su `finally` no corre y '
            'la 2 y la 3 se descartan EN SILENCIO: la pantalla deja de '
            'responder y el atleta no recibe ninguna señal.',
      );
    });

    test('las series sin confirmar igual entran al estado local', () async {
      final repo = _MockSessionRepository();
      final routine = _fourSetRoutine();
      when(() => repo.create(
            uid: any(named: 'uid'),
            routineId: any(named: 'routineId'),
            routineName: any(named: 'routineName'),
            startedAt: any(named: 'startedAt'),
            dayNumber: any(named: 'dayNumber'),
            weekNumber: any(named: 'weekNumber'),
            waitForServer: any(named: 'waitForServer'),
            onServerRejected: any(named: 'onServerRejected'),
          )).thenAnswer((_) async => makeSession());
      _gateAddSetLog(repo);

      final container = _makeContainer(repo, routine);
      addTearDown(container.dispose);

      final init = FreshSession(routineId: routine.id, dayNumber: 1);
      final sub = container.listen(
        sessionNotifierProvider(init),
        (_, __) {},
        fireImmediately: true,
      );
      addTearDown(sub.close);
      await container.read(sessionNotifierProvider(init).future);
      final notifier = container.read(sessionNotifierProvider(init).notifier);

      unawaited(notifier.logSet(makeSetLog(exerciseId: 'e1', setNumber: 1)));
      await Future<void>.delayed(Duration.zero);
      unawaited(notifier.logSet(makeSetLog(exerciseId: 'e1', setNumber: 2)));
      await Future<void>.delayed(Duration.zero);

      // En la app real el stream de Firestore también las mete (la escritura
      // entra al cache y `.snapshots()` emite). Acá el stream es vacío a
      // propósito, así que esto mide SÓLO el camino local del notifier: si
      // el atleta ve tildarse lo que marcó, sin esperar al servidor.
      final estado = container.read(sessionNotifierProvider(init)).value!;
      expect(
        estado.setLogs.map((s) => s.setNumber).toList(),
        [1, 2],
        reason: 'lo que el atleta marcó tiene que verse tildado sin esperar '
            'la confirmación del servidor. Si no, entrenar sin conexión es '
            'indistinguible de la app colgada.',
      );
    });

    test(
        'al reloj se le avisa cuando el SERVIDOR confirma, no cuando se encola '
        'la escritura', () async {
      // Hallazgo de Codex en la review del PR, y tenía razón.
      //
      // `reasonSetLogged` no le manda la serie al reloj: le pide que RELEA
      // Firestore. Avisarle apenas se encola la escritura le hace leer un
      // servidor que todavía no la tiene — el reloj queda igual de
      // desactualizado y NO hay un segundo aviso cuando la confirmación llega.
      // Con el reloj creyendo que la serie no existe, marcarla en la muñeca
      // escribe un SEGUNDO documento (los ids de los dos clientes no
      // coinciden) y vuelven los duplicados que esta sincronización existe
      // para evitar.
      //
      // Antes el orden salía gratis: el `await` sobre la escritura garantizaba
      // que el servidor ya la tenía. Al sacarlo del camino crítico hay que
      // reponerlo a mano, y esto lo fija.
      final repo = _MockSessionRepository();
      final routine = _fourSetRoutine();
      final espia = _SpyWatchNudge();
      when(() => repo.create(
            uid: any(named: 'uid'),
            routineId: any(named: 'routineId'),
            routineName: any(named: 'routineName'),
            startedAt: any(named: 'startedAt'),
            dayNumber: any(named: 'dayNumber'),
            weekNumber: any(named: 'weekNumber'),
            waitForServer: any(named: 'waitForServer'),
            onServerRejected: any(named: 'onServerRejected'),
          )).thenAnswer((_) async => makeSession());
      final acks = _gateAddSetLogConAcks(repo);

      final container = ProviderContainer(
        overrides: [
          sessionRepositoryProvider.overrideWithValue(repo),
          currentUidProvider.overrideWithValue('u1'),
          routineByIdProvider(routine.id).overrideWith((ref) async => routine),
          sessionsByUidProvider('u1').overrideWith((ref) async => const []),
          watchNudgeServiceProvider.overrideWithValue(espia),
        ],
      );
      addTearDown(container.dispose);

      final init = FreshSession(routineId: routine.id, dayNumber: 1);
      final sub = container.listen(
        sessionNotifierProvider(init),
        (_, __) {},
        fireImmediately: true,
      );
      addTearDown(sub.close);
      await container.read(sessionNotifierProvider(init).future);
      final notifier = container.read(sessionNotifierProvider(init).notifier);

      unawaited(notifier.logSet(makeSetLog(exerciseId: 'e1', setNumber: 1)));
      await Future<void>.delayed(Duration.zero);

      expect(
        espia.motivos.where((m) => m == WatchNudgeService.reasonSetLogged),
        isEmpty,
        reason: 'sin confirmación del servidor, avisarle al reloj lo manda a '
            'leer un Firestore que todavía no tiene la serie. El aviso se '
            'gasta y no hay otro.',
      );

      // Vuelve la red: Firestore sincroniza la escritura encolada.
      acks.single.complete();
      await Future<void>.delayed(Duration.zero);

      expect(
        espia.motivos.where((m) => m == WatchNudgeService.reasonSetLogged),
        hasLength(1),
        reason: 'con la serie ya en el servidor, ahí sí el reloj tiene qué '
            'releer — y es el único momento en que el aviso sirve.',
      );
    });

    test(
        'una escritura RECHAZADA por el servidor publica el error y NO avisa '
        'al reloj', () async {
      // La rama `onError` de `_onWriteSettled` no la ejercitaba NINGÚN test, y
      // es la pieza central del riesgo de este diseño: antes el error viajaba
      // por el `await` y lo agarraba un `catch`; ahora viaja por un future que
      // nadie espera. Un fallo silencioso acá se lleva la serie sin que se
      // entere nadie.
      //
      // OJO con la diferencia que este test fija: sin red el future queda
      // PENDIENTE —no falla— y no pasa por acá. Esto es el otro caso: el
      // servidor contestó que NO (un permission-denied, por ejemplo).
      final repo = _MockSessionRepository();
      final routine = _fourSetRoutine();
      final espia = _SpyWatchNudge();
      when(() => repo.create(
            uid: any(named: 'uid'),
            routineId: any(named: 'routineId'),
            routineName: any(named: 'routineName'),
            startedAt: any(named: 'startedAt'),
            dayNumber: any(named: 'dayNumber'),
            weekNumber: any(named: 'weekNumber'),
            waitForServer: any(named: 'waitForServer'),
            onServerRejected: any(named: 'onServerRejected'),
          )).thenAnswer((_) async => makeSession());
      final acks = _gateAddSetLogConAcks(repo);

      final container = ProviderContainer(
        overrides: [
          sessionRepositoryProvider.overrideWithValue(repo),
          currentUidProvider.overrideWithValue('u1'),
          routineByIdProvider(routine.id).overrideWith((ref) async => routine),
          sessionsByUidProvider('u1').overrideWith((ref) async => const []),
          watchNudgeServiceProvider.overrideWithValue(espia),
        ],
      );
      addTearDown(container.dispose);

      final init = FreshSession(routineId: routine.id, dayNumber: 1);
      final sub = container.listen(
        sessionNotifierProvider(init),
        (_, __) {},
        fireImmediately: true,
      );
      addTearDown(sub.close);
      await container.read(sessionNotifierProvider(init).future);
      final notifier = container.read(sessionNotifierProvider(init).notifier);

      unawaited(notifier.logSet(makeSetLog(exerciseId: 'e1', setNumber: 1)));
      await Future<void>.delayed(Duration.zero);
      expect(notifier.logSetError.value, isNull);

      acks.single.completeError(
        Exception('permission-denied'),
        StackTrace.current,
      );
      await Future<void>.delayed(Duration.zero);

      expect(
        notifier.logSetError.value?.action,
        SessionLogAction.log,
        reason: 'un rechazo del servidor tiene que llegar al canal de error, '
            'no perderse en un future que nadie mira.',
      );
      expect(
        notifier.logSetError.value?.setLog?.setNumber,
        1,
        reason: 'el error conserva QUÉ serie se perdió: sin eso el cartel no '
            'puede ofrecer reintentar.',
      );
      expect(
        espia.motivos.where((m) => m == WatchNudgeService.reasonSetLogged),
        isEmpty,
        reason: 'si el servidor rechazó la serie, mandar al reloj a releer '
            'Firestore no tiene ningún sentido: no hay nada que leer.',
      );
    });

    test('un mismo set marcado dos veces sigue entrando una sola vez',
        () async {
      // El guard anti doble-tap (device feedback 2026-06-12) no se puede
      // perder por el camino: sacarlo trae de vuelta los duplicados masivos.
      // La defensa que queda es la idempotencia por `exerciseId + setNumber`,
      // y este test la fija.
      final repo = _MockSessionRepository();
      final routine = _fourSetRoutine();
      when(() => repo.create(
            uid: any(named: 'uid'),
            routineId: any(named: 'routineId'),
            routineName: any(named: 'routineName'),
            startedAt: any(named: 'startedAt'),
            dayNumber: any(named: 'dayNumber'),
            weekNumber: any(named: 'weekNumber'),
            waitForServer: any(named: 'waitForServer'),
            onServerRejected: any(named: 'onServerRejected'),
          )).thenAnswer((_) async => makeSession());
      final recibidas = _gateAddSetLog(repo);

      final container = _makeContainer(repo, routine);
      addTearDown(container.dispose);

      final init = FreshSession(routineId: routine.id, dayNumber: 1);
      final sub = container.listen(
        sessionNotifierProvider(init),
        (_, __) {},
        fireImmediately: true,
      );
      addTearDown(sub.close);
      await container.read(sessionNotifierProvider(init).future);
      final notifier = container.read(sessionNotifierProvider(init).notifier);

      unawaited(notifier.logSet(makeSetLog(exerciseId: 'e1', setNumber: 1)));
      await Future<void>.delayed(Duration.zero);
      unawaited(notifier.logSet(makeSetLog(exerciseId: 'e1', setNumber: 1)));
      await Future<void>.delayed(Duration.zero);

      expect(
        recibidas.length,
        1,
        reason: 'la misma serie marcada dos veces se escribe UNA. Sin esto '
            'vuelven los sets duplicados masivos del 2026-06-12.',
      );
    });
  });
}
