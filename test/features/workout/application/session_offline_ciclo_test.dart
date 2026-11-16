// session_offline_ciclo_test.dart — un entreno de punta a punta sin conexión.
//
// ─── Qué falta después de #1179 ─────────────────────────────────────────────
//
// El #1179 arregló MARCAR una serie. Pero entrenar es empezar, marcar y
// terminar, y los otros dos seguían esperando al servidor:
//
//   • `SessionNotifier.build` → `repo.create(...)` con `waitForServer` en su
//     default `true`. Sin red el `await` no resuelve nunca y el player queda
//     en `AsyncLoading` PARA SIEMPRE: el atleta toca Empezar y mira un spinner
//     que no termina. No hay excepción, no hay reintento, no hay salida.
//
//   • `finishSession` / `abandonSession` → `repo.finish(...)`. Peor todavía,
//     porque el notifier pone `_finalized = true` ANTES del await (el guard
//     anti doble-finish). Sin red el await no vuelve, así que `_finalize()` no
//     corre y el `catch` que resetea `_finalized` tampoco: la sesión queda con
//     el flag trabado, `logSet`/`updateSet`/`removeSet`/`addSet` pasan a ser
//     NO-OPS SILENCIOSOS, el cronómetro sigue corriendo y nunca se navega al
//     resumen. Es el mismo bug del #1179 —guard trabado, descarte mudo— un
//     nivel más arriba, y se lleva el entreno entero.
//
// ─── Por qué el doble se cuelga SÓLO con waitForServer: true ────────────────
//
// Es deliberado, y es lo que vuelve útil a este archivo.
//
// Un doble que contesta siempre probaría el doble, no el código: el test
// pasaría aunque el notifier siguiera pidiendo la confirmación del servidor.
// Es exactamente el agujero que tuvimos en el #1179 —tests que mockeaban
// `addSetLog` entero y por eso no veían lo que hacía el repositorio—.
//
// Acá el doble replica el CONTRATO real: con `waitForServer: true` Firestore
// no contesta sin red, con `false` la escritura se aplica al caché y vuelve al
// instante. Así, la única forma de que estos tests pasen es que el notifier
// pase el flag de verdad.

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/features/workout/application/routine_providers.dart';
import 'package:treino/features/workout/application/session_init.dart';
import 'package:treino/features/workout/application/session_notifier.dart';
import 'package:treino/features/workout/application/session_providers.dart';
import 'package:treino/features/workout/data/session_repository.dart';
import 'package:treino/features/workout/domain/routine.dart';
import 'package:treino/features/workout/domain/session.dart';
import 'package:treino/features/workout/domain/set_log.dart';

import 'stub_factories.dart';

class _MockSessionRepository extends Mock implements SessionRepository {
  /// Lo que emite `watchSetLogs`. Vacío salvo que un test lo cambie.
  Stream<List<SetLog>> setLogsStream = const Stream<List<SetLog>>.empty();

  @override
  Stream<List<SetLog>> watchSetLogs({
    required String uid,
    required String sessionId,
  }) =>
      setLogsStream;

  /// Lo que emite `watchSessionFinished`. Vacío salvo que un test lo cambie.
  Stream<bool> finishedStream = const Stream<bool>.empty();

  @override
  Stream<bool> watchSessionFinished({
    required String uid,
    required String sessionId,
  }) =>
      finishedStream;
}

Routine _routine() => makeRoutine(
      days: [
        makeDay(slots: [makeSlot(exerciseId: 'e1', targetSets: 2)])
      ],
    );

/// Un repositorio EN MODO AVIÓN.
///
/// `create` y `finish` se cuelgan si el caller pide esperar al servidor, y
/// contestan al instante si no. Es el contrato de Firestore sin red.
void _modoAvion(_MockSessionRepository repo) {
  when(() => repo.create(
        uid: any(named: 'uid'),
        routineId: any(named: 'routineId'),
        routineName: any(named: 'routineName'),
        startedAt: any(named: 'startedAt'),
        dayNumber: any(named: 'dayNumber'),
        weekNumber: any(named: 'weekNumber'),
        waitForServer: any(named: 'waitForServer'),
        onServerRejected: any(named: 'onServerRejected'),
      )).thenAnswer((inv) {
    final espera = inv.namedArguments[#waitForServer] as bool? ?? true;
    if (espera) return Completer<Session>().future;
    return Future<Session>.value(makeSession());
  });

  when(() => repo.finish(
        uid: any(named: 'uid'),
        sessionId: any(named: 'sessionId'),
        finishedAt: any(named: 'finishedAt'),
        totalVolumeKg: any(named: 'totalVolumeKg'),
        durationMin: any(named: 'durationMin'),
        wasFullyCompleted: any(named: 'wasFullyCompleted'),
        weeklyTarget: any(named: 'weeklyTarget'),
        waitForServer: any(named: 'waitForServer'),
        onServerRejected: any(named: 'onServerRejected'),
      )).thenAnswer((inv) {
    final espera = inv.namedArguments[#waitForServer] as bool? ?? true;
    if (espera) return Completer<void>().future;
    return Future<void>.value();
  });

  when(() => repo.addSetLog(
        uid: any(named: 'uid'),
        sessionId: any(named: 'sessionId'),
        setLog: any(named: 'setLog'),
      )).thenAnswer((inv) {
    final pedida = inv.namedArguments[#setLog] as SetLog;
    return Future<LoggedSet>.value(
      LoggedSet(
        setLog: pedida.copyWith(id: 'doc-${pedida.setNumber}'),
        // Sin red la confirmación no llega nunca (lo fija #1179).
        acknowledged: Completer<void>().future,
      ),
    );
  });
}

ProviderContainer _container(_MockSessionRepository repo, Routine routine) =>
    ProviderContainer(
      overrides: [
        sessionRepositoryProvider.overrideWithValue(repo),
        currentUidProvider.overrideWithValue('u1'),
        routineByIdProvider(routine.id).overrideWith((ref) async => routine),
        sessionsByUidProvider('u1').overrideWith((ref) async => const []),
      ],
    );

void main() {
  setUpAll(() {
    registerFallbackValue(makeSession());
    registerFallbackValue(makeSetLog());
    registerFallbackValue(DateTime.utc(2026));
  });

  group('un entreno de punta a punta sin conexión', () {
    test('se puede EMPEZAR: el player no queda en AsyncLoading para siempre',
        () async {
      final repo = _MockSessionRepository();
      final routine = _routine();
      _modoAvion(repo);

      final container = _container(repo, routine);
      addTearDown(container.dispose);

      final init = FreshSession(routineId: routine.id, dayNumber: 1);
      final sub = container.listen(
        sessionNotifierProvider(init),
        (_, __) {},
        fireImmediately: true,
      );
      addTearDown(sub.close);

      // La cota es del TEST, no de la app: sin red el atleta se queda mirando
      // el spinner sin que nadie le corte a los 5 segundos.
      final estado =
          await container.read(sessionNotifierProvider(init).future).timeout(
                const Duration(seconds: 5),
                onTimeout: () => throw StateError(
                  'el player se quedó colgado arrancando el entreno: `create` '
                  'está esperando una confirmación del servidor que sin red no '
                  'llega nunca',
                ),
              );

      expect(estado.session.status.name, 'active');
    });

    test('se puede TERMINAR: finishSession vuelve y no deja el guard trabado',
        () async {
      final repo = _MockSessionRepository();
      final routine = _routine();
      _modoAvion(repo);

      final container = _container(repo, routine);
      addTearDown(container.dispose);

      final init = FreshSession(routineId: routine.id, dayNumber: 1);
      final sub = container.listen(
        sessionNotifierProvider(init),
        (_, __) {},
        fireImmediately: true,
      );
      addTearDown(sub.close);
      await container
          .read(sessionNotifierProvider(init).future)
          .timeout(const Duration(seconds: 5));
      final notifier = container.read(sessionNotifierProvider(init).notifier);

      // `finishSession` exige la rutina completa, así que se marcan las dos
      // series antes. Sin esto el test falla por el guard de completitud y no
      // por lo que quiere medir.
      unawaited(notifier.logSet(makeSetLog(exerciseId: 'e1', setNumber: 1)));
      await Future<void>.delayed(Duration.zero);
      unawaited(notifier.logSet(makeSetLog(exerciseId: 'e1', setNumber: 2)));
      await Future<void>.delayed(Duration.zero);

      await notifier.finishSession().timeout(
            const Duration(seconds: 5),
            onTimeout: () => throw StateError(
              'terminar el entreno se colgó. Y el daño no es sólo que no '
              'navegue: `_finalized` quedó en true antes del await, así que '
              'marcar, editar y borrar series pasan a ser no-ops silenciosos '
              'y el cronómetro sigue corriendo.',
            ),
          );

      verify(() => repo.finish(
            uid: any(named: 'uid'),
            sessionId: any(named: 'sessionId'),
            finishedAt: any(named: 'finishedAt'),
            totalVolumeKg: any(named: 'totalVolumeKg'),
            durationMin: any(named: 'durationMin'),
            wasFullyCompleted: any(named: 'wasFullyCompleted'),
            weeklyTarget: any(named: 'weeklyTarget'),
            waitForServer: false,
            onServerRejected: any(named: 'onServerRejected'),
          )).called(1);
    });

    test('se puede ABANDONAR sin quedar trabado', () async {
      // Mismo camino que terminar, y también pone `_finalized` antes del await.
      final repo = _MockSessionRepository();
      final routine = _routine();
      _modoAvion(repo);

      final container = _container(repo, routine);
      addTearDown(container.dispose);

      final init = FreshSession(routineId: routine.id, dayNumber: 1);
      final sub = container.listen(
        sessionNotifierProvider(init),
        (_, __) {},
        fireImmediately: true,
      );
      addTearDown(sub.close);
      await container
          .read(sessionNotifierProvider(init).future)
          .timeout(const Duration(seconds: 5));
      final notifier = container.read(sessionNotifierProvider(init).notifier);

      await notifier.abandonSession().timeout(
            const Duration(seconds: 5),
            onTimeout: () => throw StateError(
              'abandonar el entreno se colgó por esperar al servidor',
            ),
          );
    });

    test(
        'cuando el reloj cierra el entreno, el teléfono se entera (el lado '
        'POSITIVO del aviso)', () async {
      // Este test existe porque el archivo sólo probaba que la defensa
      // BLOQUEA, y ninguno que DEJA PASAR: `rg finishedElsewhere test/` daba
      // un único hit, y era una aserción negativa.
      //
      // Sin este par, una defensa que bloqueara TODO —incluido el aviso
      // legítimo del reloj— dejaba la suite en verde y rompía en silencio la
      // función entera de «cerrar desde la muñeca».
      final repo = _MockSessionRepository();
      final routine = _routine();
      final finished = StreamController<bool>.broadcast();
      addTearDown(finished.close);
      repo.finishedStream = finished.stream;
      _modoAvion(repo);

      final container = _container(repo, routine);
      addTearDown(container.dispose);
      final init = FreshSession(routineId: routine.id, dayNumber: 1);
      final sub = container.listen(
        sessionNotifierProvider(init),
        (_, __) {},
        fireImmediately: true,
      );
      addTearDown(sub.close);
      await container
          .read(sessionNotifierProvider(init).future)
          .timeout(const Duration(seconds: 5));
      final notifier = container.read(sessionNotifierProvider(init).notifier);

      expect(notifier.finishedElsewhere.value, isFalse);

      // `watchSessionFinished` ya resolvió que esto es un cierre de verdad:
      // decidir si la desaparición del documento cuenta es responsabilidad del
      // repositorio, y se prueba en session_repository_finished_source_test.
      finished.add(true);
      await Future<void>.delayed(Duration.zero);

      expect(
        notifier.finishedElsewhere.value,
        isTrue,
        reason: 'es el camino por el que el atleta se entera de que cerró el '
            'entreno desde la muñeca. Si el notifier lo ignora, sigue '
            'entrenando sobre una sesión que ya no existe.',
      );
    });

    test('un create RECHAZADO llega a la pantalla como error, no como silencio',
        () async {
      final repo = _MockSessionRepository();
      final routine = _routine();
      late void Function(Object) rechazar;
      when(() => repo.create(
            uid: any(named: 'uid'),
            routineId: any(named: 'routineId'),
            routineName: any(named: 'routineName'),
            startedAt: any(named: 'startedAt'),
            dayNumber: any(named: 'dayNumber'),
            weekNumber: any(named: 'weekNumber'),
            waitForServer: any(named: 'waitForServer'),
            onServerRejected: any(named: 'onServerRejected'),
          )).thenAnswer((inv) {
        rechazar =
            inv.namedArguments[#onServerRejected] as void Function(Object);
        return Future<Session>.value(makeSession());
      });

      final container = _container(repo, routine);
      addTearDown(container.dispose);
      final init = FreshSession(routineId: routine.id, dayNumber: 1);
      final sub = container.listen(
        sessionNotifierProvider(init),
        (_, __) {},
        fireImmediately: true,
      );
      addTearDown(sub.close);
      await container
          .read(sessionNotifierProvider(init).future)
          .timeout(const Duration(seconds: 5));

      rechazar(Exception('permission-denied'));
      await Future<void>.delayed(Duration.zero);

      expect(
        container.read(sessionNotifierProvider(init)).hasError,
        isTrue,
        reason: 'el atleta tiene que ENTERARSE, no entrenar media hora contra '
            'una sesión que el servidor nunca aceptó.',
      );
    });

    test(
        'un create RECHAZADO frena el reloj: el tick no pisa el error con un '
        'AsyncData (#1805)', () {
      // `state = AsyncError(...)` conserva el dato anterior (`hasValue` sigue
      // en true), así que `state.value` NO tira: devuelve la sesión vieja y el
      // tick la reescribía como `AsyncData`, borrando el aviso un segundo
      // después de mostrarlo.
      fakeAsync((async) {
        final repo = _MockSessionRepository();
        final routine = _routine();
        late void Function(Object) rechazar;
        when(() => repo.create(
              uid: any(named: 'uid'),
              routineId: any(named: 'routineId'),
              routineName: any(named: 'routineName'),
              startedAt: any(named: 'startedAt'),
              dayNumber: any(named: 'dayNumber'),
              weekNumber: any(named: 'weekNumber'),
              waitForServer: any(named: 'waitForServer'),
              onServerRejected: any(named: 'onServerRejected'),
            )).thenAnswer((inv) {
          rechazar =
              inv.namedArguments[#onServerRejected] as void Function(Object);
          return Future<Session>.value(makeSession());
        });

        final container = _container(repo, routine);
        final init = FreshSession(routineId: routine.id, dayNumber: 1);
        final sub = container.listen(
          sessionNotifierProvider(init),
          (_, __) {},
          fireImmediately: true,
        );
        async.flushMicrotasks();
        expect(container.read(sessionNotifierProvider(init)).hasValue, isTrue);
        expect(async.periodicTimerCount, 1, reason: 'el reloj está corriendo');

        rechazar(Exception('permission-denied'));
        async.flushMicrotasks();
        expect(container.read(sessionNotifierProvider(init)).hasError, isTrue);

        // Tres ticks del reloj.
        async.elapse(const Duration(seconds: 3));

        expect(
          container.read(sessionNotifierProvider(init)).hasError,
          isTrue,
          reason: 'el tick no puede pisar el error con un AsyncData: el '
              'atleta dejaría de ver la salida.',
        );
        expect(
          async.periodicTimerCount,
          0,
          reason: 'en error no hay nada que cronometrar: el reloj se frena.',
        );

        sub.close();
        container.dispose();
      });
    });

    // #1805/#1810 arregló el reloj. Las mutaciones de series y el reconciliador
    // del stream tenían el MISMO problema: `state = AsyncError(...)` conserva el
    // dato anterior, así que `state.value` devuelve la sesión vieja sin tirar y
    // el `state = AsyncData(...)` que sigue borra el aviso de «el servidor
    // rechazó tu entreno».
    group('con el create RECHAZADO, nada pisa el error con un AsyncData', () {
      late _MockSessionRepository repo;
      late ProviderContainer container;
      late FreshSession init;
      late SessionNotifier notifier;
      late void Function(Object) rechazar;
      late StreamController<List<SetLog>> remoto;

      AsyncValue<dynamic> estado() =>
          container.read(sessionNotifierProvider(init));

      Future<void> turno() => Future<void>.delayed(Duration.zero);

      setUp(() async {
        repo = _MockSessionRepository();
        final routine = _routine();
        remoto = StreamController<List<SetLog>>.broadcast();
        addTearDown(remoto.close);
        repo.setLogsStream = remoto.stream;

        when(() => repo.create(
              uid: any(named: 'uid'),
              routineId: any(named: 'routineId'),
              routineName: any(named: 'routineName'),
              startedAt: any(named: 'startedAt'),
              dayNumber: any(named: 'dayNumber'),
              weekNumber: any(named: 'weekNumber'),
              waitForServer: any(named: 'waitForServer'),
              onServerRejected: any(named: 'onServerRejected'),
            )).thenAnswer((inv) {
          rechazar =
              inv.namedArguments[#onServerRejected] as void Function(Object);
          return Future<Session>.value(makeSession());
        });
        when(() => repo.addSetLog(
              uid: any(named: 'uid'),
              sessionId: any(named: 'sessionId'),
              setLog: any(named: 'setLog'),
            )).thenAnswer((inv) async => LoggedSet(
              setLog:
                  (inv.namedArguments[#setLog] as SetLog).copyWith(id: 'doc-1'),
              acknowledged: Future<void>.value(),
            ));
        when(() => repo.updateSetLog(
              uid: any(named: 'uid'),
              sessionId: any(named: 'sessionId'),
              setLog: any(named: 'setLog'),
            )).thenAnswer((_) async {});
        when(() => repo.deleteSetLog(
              uid: any(named: 'uid'),
              sessionId: any(named: 'sessionId'),
              setLogId: any(named: 'setLogId'),
            )).thenAnswer((_) async {});

        container = _container(repo, routine);
        addTearDown(container.dispose);
        init = FreshSession(routineId: routine.id, dayNumber: 1);
        final sub = container.listen(
          sessionNotifierProvider(init),
          (_, __) {},
          fireImmediately: true,
        );
        addTearDown(sub.close);
        await container.read(sessionNotifierProvider(init).future);
        notifier = container.read(sessionNotifierProvider(init).notifier);
      });

      void rechazarElCreate() {
        rechazar(Exception('permission-denied'));
      }

      test('control: SIN error, marcar una serie la guarda en el estado',
          () async {
        await notifier.logSet(makeSetLog());

        verify(() => repo.addSetLog(
              uid: any(named: 'uid'),
              sessionId: any(named: 'sessionId'),
              setLog: any(named: 'setLog'),
            )).called(1);
        expect(estado().hasError, isFalse);
        expect(estado().requireValue.setLogs, hasLength(1));
      });

      test('logSet no escribe y no pisa el error', () async {
        rechazarElCreate();
        await turno();
        expect(estado().hasError, isTrue);

        await notifier.logSet(makeSetLog());

        verifyNever(() => repo.addSetLog(
              uid: any(named: 'uid'),
              sessionId: any(named: 'sessionId'),
              setLog: any(named: 'setLog'),
            ));
        expect(estado().hasError, isTrue,
            reason: 'el atleta tiene que seguir viendo el rechazo');
      });

      test('updateSet no escribe y no pisa el error', () async {
        rechazarElCreate();
        await turno();

        await notifier.updateSet(makeSetLog(id: 'doc-1'));

        verifyNever(() => repo.updateSetLog(
              uid: any(named: 'uid'),
              sessionId: any(named: 'sessionId'),
              setLog: any(named: 'setLog'),
            ));
        expect(estado().hasError, isTrue);
      });

      test('addSet y removeSet no pisan el error', () async {
        final slot = makeSlot(exerciseId: 'e1', targetSets: 2);
        rechazarElCreate();
        await turno();

        await notifier.addSet(slot);
        await notifier.removeSet(slot, makeSetLog(id: 'doc-1'));

        verifyNever(() => repo.deleteSetLog(
              uid: any(named: 'uid'),
              sessionId: any(named: 'sessionId'),
              setLogId: any(named: 'setLogId'),
            ));
        expect(estado().hasError, isTrue);
      });

      test('un snapshot del stream de series no pisa el error', () async {
        rechazarElCreate();
        await turno();

        remoto.add([makeSetLog(id: 'doc-9', setNumber: 1)]);
        await turno();

        expect(estado().hasError, isTrue,
            reason: 'el reconciliador remoto reescribía la sesión como '
                'AsyncData con el dato viejo');
      });

      test(
          'si el rechazo llega MIENTRAS se escribe una serie, la serie no '
          'pisa el error al volver', () async {
        final enVuelo = Completer<LoggedSet>();
        when(() => repo.addSetLog(
              uid: any(named: 'uid'),
              sessionId: any(named: 'sessionId'),
              setLog: any(named: 'setLog'),
            )).thenAnswer((_) => enVuelo.future);

        final marcando = notifier.logSet(makeSetLog());
        await turno();
        rechazarElCreate(); // el servidor rechaza con la escritura en vuelo
        await turno();
        expect(estado().hasError, isTrue);

        enVuelo.complete(LoggedSet(
          setLog: makeSetLog(id: 'doc-1'),
          acknowledged: Future<void>.value(),
        ));
        await marcando;

        expect(estado().hasError, isTrue,
            reason: 'la escritura que volvió no puede reescribir el estado');
      });
    });

    test('el ciclo completo: empezar → marcar → terminar', () async {
      // El caso del atleta, entero. Cada pieza tiene su test arriba; ésta
      // existe porque las tres juntas son la promesa, y una cadena se corta
      // en el eslabón que nadie probó completo.
      final repo = _MockSessionRepository();
      final routine = _routine();
      _modoAvion(repo);

      final container = _container(repo, routine);
      addTearDown(container.dispose);

      final init = FreshSession(routineId: routine.id, dayNumber: 1);
      final sub = container.listen(
        sessionNotifierProvider(init),
        (_, __) {},
        fireImmediately: true,
      );
      addTearDown(sub.close);

      await container
          .read(sessionNotifierProvider(init).future)
          .timeout(const Duration(seconds: 5));
      final notifier = container.read(sessionNotifierProvider(init).notifier);

      unawaited(notifier.logSet(makeSetLog(exerciseId: 'e1', setNumber: 1)));
      await Future<void>.delayed(Duration.zero);
      unawaited(notifier.logSet(makeSetLog(exerciseId: 'e1', setNumber: 2)));
      await Future<void>.delayed(Duration.zero);

      final estado = container.read(sessionNotifierProvider(init)).value!;
      expect(
        estado.setLogs.map((s) => s.setNumber).toList(),
        [1, 2],
        reason: 'las dos series marcadas tienen que verse tildadas sin red',
      );

      await notifier.finishSession().timeout(
            const Duration(seconds: 5),
            onTimeout: () => throw StateError(
              'el entreno se marcó entero pero no se pudo cerrar',
            ),
          );
    });
  });
}
