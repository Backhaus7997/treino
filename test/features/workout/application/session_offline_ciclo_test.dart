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

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/features/workout/application/routine_providers.dart';
import 'package:treino/features/workout/application/session_init.dart';
import 'package:treino/features/workout/application/session_providers.dart';
import 'package:treino/features/workout/data/session_repository.dart';
import 'package:treino/features/workout/domain/routine.dart';
import 'package:treino/features/workout/domain/session.dart';
import 'package:treino/features/workout/domain/set_log.dart';

import 'stub_factories.dart';

class _MockSessionRepository extends Mock implements SessionRepository {
  @override
  Stream<List<SetLog>> watchSetLogs({
    required String uid,
    required String sessionId,
  }) =>
      const Stream<List<SetLog>>.empty();

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
        onServerConfirmed: any(named: 'onServerConfirmed'),
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
        'un create RECHAZADO no se disfraza de «lo cerró el reloj», aunque el '
        'snapshot llegue primero', () async {
      // Un create rechazado dispara DOS canales del SDK sin orden garantizado:
      // el snapshot que revierte el caché (y hace desaparecer el doc) y el
      // future de la escritura que falla. `watchSessionFinished` lee «el doc
      // no existe» como «terminada», así que si el snapshot gana, la pantalla
      // le dice al atleta que terminó el entreno desde la muñeca — sobre un
      // rechazo de paywall.
      //
      // Este test fuerza el orden PEOR: el stream emite `true` ANTES de que
      // llegue el rechazo. Una defensa que se prenda con el rechazo no puede
      // pasarlo; sólo lo pasa invertir la polaridad y no creerle a la
      // desaparición hasta que el servidor confirmó que la sesión existe.
      final repo = _MockSessionRepository();
      final routine = _routine();
      final finished = StreamController<bool>.broadcast();
      addTearDown(finished.close);
      repo.finishedStream = finished.stream;

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
            onServerConfirmed: any(named: 'onServerConfirmed'),
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
      final notifier = container.read(sessionNotifierProvider(init).notifier);

      // El SNAPSHOT gana: el doc desapareció porque el SDK revirtió.
      finished.add(true);
      await Future<void>.delayed(Duration.zero);

      expect(
        notifier.finishedElsewhere.value,
        isFalse,
        reason: 'la sesión nunca se confirmó en el servidor, así que su '
            'desaparición NO significa que alguien la haya terminado. '
            'Decirle al atleta que cerró el entreno desde el reloj sobre un '
            'rechazo es una explicación falsa, peor que ninguna.',
      );

      // Y recién ahora llega el rechazo por el otro canal.
      rechazar(Exception('permission-denied'));
      await Future<void>.delayed(Duration.zero);

      expect(
        container.read(sessionNotifierProvider(init)).hasError,
        isTrue,
        reason: 'el rechazo tiene que llegar a la pantalla como error, con su '
            'motivo real y su reintento.',
      );
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
