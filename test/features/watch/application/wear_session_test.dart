import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:mocktail/mocktail.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/profile/domain/experience_level.dart';
import 'package:treino/features/watch/application/wear_rest_providers.dart';
import 'package:treino/features/watch/application/wear_session_providers.dart';
import 'package:treino/features/watch/data/wear_workout_service.dart';
import 'package:treino/features/watch/presentation/wear/wear_view_models.dart';
import 'package:treino/features/workout/application/routine_providers.dart';
import 'package:treino/features/workout/application/session_providers.dart';
import 'package:treino/features/workout/data/session_repository.dart';
import 'package:treino/features/workout/domain/routine.dart';
import 'package:treino/features/workout/domain/routine_day.dart';
import 'package:treino/features/workout/domain/routine_slot.dart';
import 'package:treino/features/workout/domain/set_log.dart';
import 'package:treino/features/workout/domain/set_log_identity.dart';

class _MockWorkoutService extends Mock implements WearWorkoutService {}

/// Un repo cuyo `addSetLogFromWatch` NUNCA completa, como pasa cuando Firestore
/// no puede confirmar contra el servidor. Todo lo demás delega.
class _RepoQueNoVuelve implements SessionRepository {
  _RepoQueNoVuelve(this._real, this._colgada);

  final SessionRepository _real;
  final Future<SetLog?> _colgada;

  @override
  Future<SetLog?> addSetLogFromWatch({
    required String uid,
    required String sessionId,
    required SetLog setLog,
    List<RemoteSetLogRef>? knownRemote,
  }) =>
      _colgada;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      reflectDelegate(_real, invocation);
}

/// Delegación manual: `SessionRepository` no es una interfaz chica y sólo hace
/// falta redirigir lo que el notifier usa.
dynamic reflectDelegate(SessionRepository real, Invocation i) {
  final n = i.memberName.toString();
  if (n.contains('getActive')) {
    return real.getActive(i.positionalArguments.first as String);
  }
  if (n.contains('create')) {
    return real.create(
      uid: i.namedArguments[#uid] as String,
      routineId: i.namedArguments[#routineId] as String,
      routineName: i.namedArguments[#routineName] as String,
      startedAt: i.namedArguments[#startedAt] as DateTime,
      dayNumber: i.namedArguments[#dayNumber] as int? ?? 1,
      weekNumber: i.namedArguments[#weekNumber] as int? ?? 0,
    );
  }
  if (n.contains('watchSetLogs')) {
    return real.watchSetLogs(
      uid: i.namedArguments[#uid] as String,
      sessionId: i.namedArguments[#sessionId] as String,
    );
  }
  throw UnimplementedError('sin delegar: \$n');
}

const uid = 'atleta-1';

RoutineSlot _slot(String nombre, {int series = 3, int rest = 60}) =>
    RoutineSlot(
      exerciseId: nombre,
      exerciseName: nombre,
      muscleGroup: 'chest',
      targetSets: series,
      targetRepsMin: 8,
      targetRepsMax: 12,
      restSeconds: rest,
    );

final rutina = Routine(
  id: 'r1',
  name: 'Fuerza Base',
  level: ExperienceLevel.beginner,
  numWeeks: 1,
  days: [
    RoutineDay(
        dayNumber: 1, name: 'Empuje', slots: [_slot('press', series: 4)]),
    RoutineDay(dayNumber: 2, name: 'Tirón', slots: [
      _slot('remo', series: 3),
      _slot('curl', series: 2),
    ]),
  ],
);

const hoy = WearTodaysWorkout(
  routineId: 'r1',
  dayName: 'Empuje',
  dayNumber: 1,
  routineName: 'Fuerza Base',
  exercises: [WearExercisePreview(name: 'press', setCount: 4)],
  weekNumber: 0,
  numWeeks: 1,
);

void main() {
  late FakeFirebaseFirestore firestore;
  late SessionRepository repo;
  late _MockWorkoutService nativo;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    repo = SessionRepository(firestore: firestore);
    nativo = _MockWorkoutService();
    when(() => nativo.startWorkout()).thenAnswer((_) async => true);
    when(() => nativo.stopWorkout()).thenAnswer((_) async {});
    when(() => nativo.cancelRest()).thenAnswer((_) async {});
  });

  /// [sinRutina] distingue "no la pasaron" de "la rutina NO existe". Con un
  /// `?? rutina` el caso nulo era inalcanzable y el test pasaba sin probar nada.
  ProviderContainer contenedor({bool sinRutina = false}) {
    final c = ProviderContainer(
      overrides: [
        currentUidProvider.overrideWithValue(uid),
        sessionRepositoryProvider.overrideWithValue(repo),
        routineByIdProvider
            .overrideWith((ref, id) async => sinRutina ? null : rutina),
        wearWorkoutServiceProvider.overrideWithValue(nativo),
      ],
    );
    addTearDown(c.dispose);
    c.listen(wearSessionProvider, (_, __) {});
    return c;
  }

  Future<int> sesionesActivas() async {
    final snap = await firestore
        .collection('users')
        .doc(uid)
        .collection('sessions')
        .get();
    return snap.docs.where((d) => d.data()['status'] == 'active').length;
  }

  group('empezar', () {
    test('sin nada abierto crea UNA sesión con la posición de HOY', () async {
      final c = contenedor();
      await pumpEventQueue();

      await c.read(wearSessionProvider.notifier).start(hoy);
      await pumpEventQueue();

      final estado = c.read(wearSessionProvider);
      expect(estado, isA<WearSessionRunning>());
      final s = (estado as WearSessionRunning).session;
      expect(s.plan.dayNumber, 1);
      expect(s.plan.dayName, 'Empuje');
      expect(s.plan.plannedSets, [4]);
      expect(await sesionesActivas(), 1);
    });

    test('con una sesión del TELÉFONO abierta la adopta, y NO crea otra',
        () async {
      // La regla que evita el daño: crear a ciegas dejaría DOS activas, y el
      // barrido de getActive cierra la que no es la más nueva — o sea, la del
      // teléfono, con series cargadas y el atleta adentro.
      await repo.create(
        uid: uid,
        routineId: 'r1',
        routineName: 'Fuerza Base',
        startedAt: DateTime.utc(2026, 8, 18, 9),
        dayNumber: 2,
        weekNumber: 0,
      );

      final c = contenedor();
      await pumpEventQueue();

      await c.read(wearSessionProvider.notifier).start(hoy);
      await pumpEventQueue();

      expect(await sesionesActivas(), 1, reason: 'no se creó una segunda');

      // Y el plan es el del día de la SESIÓN (2), no el de HOY (1). Ése fue el
      // bug más caro del lado Apple.
      final s = (c.read(wearSessionProvider) as WearSessionRunning).session;
      expect(s.plan.dayNumber, 2);
      expect(s.plan.dayName, 'Tirón');
      expect(s.plan.plannedSets, [3, 2]);
    });

    test('si el entreno aparece DESPUÉS de abrir el reloj, igual lo adopta',
        () async {
      // El caso que aísla el guard de `start`, y es el realista: el atleta abre
      // el reloj (todavía no hay nada), después empieza en el TELÉFONO, y recién
      // entonces toca Empezar en la muñeca. La adopción del arranque ya pasó, así
      // que lo único que evita la segunda sesión es el getActive de `start`.
      final c = contenedor();
      await pumpEventQueue();
      expect(c.read(wearSessionProvider), isA<WearSessionIdle>());

      await repo.create(
        uid: uid,
        routineId: 'r1',
        routineName: 'Fuerza Base',
        startedAt: DateTime.utc(2026, 8, 18, 9),
        dayNumber: 2,
        weekNumber: 0,
      );

      await c.read(wearSessionProvider.notifier).start(hoy);
      await pumpEventQueue();

      expect(await sesionesActivas(), 1, reason: 'no se creó una segunda');
      final s = (c.read(wearSessionProvider) as WearSessionRunning).session;
      expect(s.plan.dayName, 'Tirón', reason: 'adoptó la del teléfono');
    });

    test('empezar dos veces no crea dos sesiones', () async {
      final c = contenedor();
      await pumpEventQueue();

      final n = c.read(wearSessionProvider.notifier);
      await n.start(hoy);
      await pumpEventQueue();
      await n.start(hoy);
      await pumpEventQueue();

      expect(await sesionesActivas(), 1);
    });
  });

  group('adoptar al arrancar la app', () {
    test('si ya hay un entreno abierto, el reloj entra directo en él',
        () async {
      await repo.create(
        uid: uid,
        routineId: 'r1',
        routineName: 'Fuerza Base',
        startedAt: DateTime.utc(2026, 8, 18, 9),
        dayNumber: 2,
        weekNumber: 0,
      );

      final c = contenedor();
      await pumpEventQueue();

      // Sin llamar start: el reloj se reinició en medio del entreno.
      final estado = c.read(wearSessionProvider);
      expect(estado, isA<WearSessionRunning>());
      expect((estado as WearSessionRunning).session.plan.dayName, 'Tirón');
    });

    test('si el uid llega TARDE, igual adopta', () async {
      // La carrera que se vio en el reloj. `currentUidProvider` sale de
      // authStateChangesProvider, que es un stream: cuando el notifier se
      // construye, Firebase Auth todavía no restauró la sesión y el uid es
      // null. Leerlo una sola vez dejaba al reloj mostrando HOY con un entreno
      // abierto, y sólo se recuperaba tocando Empezar.
      await repo.create(
        uid: uid,
        routineId: 'r1',
        routineName: 'Fuerza Base',
        startedAt: DateTime.utc(2026, 8, 18, 9),
        dayNumber: 2,
        weekNumber: 0,
      );

      final uidTardio = StateProvider<String?>((ref) => null);
      final c = ProviderContainer(
        overrides: [
          currentUidProvider.overrideWith((ref) => ref.watch(uidTardio)),
          sessionRepositoryProvider.overrideWithValue(repo),
          routineByIdProvider.overrideWith((ref, id) async => rutina),
          wearWorkoutServiceProvider.overrideWithValue(nativo),
        ],
      );
      addTearDown(c.dispose);
      c.listen(wearSessionProvider, (_, __) {});

      await pumpEventQueue();
      expect(c.read(wearSessionProvider), isA<WearSessionIdle>(),
          reason: 'sin uid todavía no hay nada que adoptar');

      // Firebase Auth restaura la sesión.
      c.read(uidTardio.notifier).state = uid;
      await pumpEventQueue();

      final estado = c.read(wearSessionProvider);
      expect(estado, isA<WearSessionRunning>());
      expect((estado as WearSessionRunning).session.plan.dayName, 'Tirón');
    });

    test('sin nada abierto se queda en HOY', () async {
      final c = contenedor();
      await pumpEventQueue();

      expect(c.read(wearSessionProvider), isA<WearSessionIdle>());
    });
  });

  group('cuando no se puede abrir', () {
    test('una rutina que ya no existe lo dice, no se cuelga', () async {
      final c = contenedor(sinRutina: true);
      await pumpEventQueue();

      await c.read(wearSessionProvider.notifier).start(hoy);
      await pumpEventQueue();

      expect(c.read(wearSessionProvider), isA<WearSessionFailed>());
    });

    test('un día que la rutina no tiene lo dice', () async {
      await repo.create(
        uid: uid,
        routineId: 'r1',
        routineName: 'Fuerza Base',
        startedAt: DateTime.utc(2026, 8, 18, 9),
        dayNumber: 9,
        weekNumber: 0,
      );

      final c = contenedor();
      await pumpEventQueue();

      expect(c.read(wearSessionProvider), isA<WearSessionFailed>());
    });
  });

  group('marcar series', () {
    Future<WearSessionRunning> arrancado(ProviderContainer c) async {
      await pumpEventQueue();
      await c.read(wearSessionProvider.notifier).start(hoy);
      await pumpEventQueue();
      return c.read(wearSessionProvider) as WearSessionRunning;
    }

    Future<List<Map<String, dynamic>>> docsDeSeries(String sessionId) async {
      final snap = await firestore
          .collection('users')
          .doc(uid)
          .collection('sessions')
          .doc(sessionId)
          .collection('setLogs')
          .get();
      return [for (final d in snap.docs) d.data()];
    }

    test('escribe con id determinístico y mueve el cursor', () async {
      final c = contenedor();
      final corriendo = await arrancado(c);
      final sid = corriendo.session.sessionId;

      final n = c.read(wearSessionProvider.notifier);
      for (var i = 1; i <= 4; i++) {
        await n.logSet(exerciseId: 'press', setNumber: i);
      }
      await pumpEventQueue();

      final docs = await docsDeSeries(sid);
      expect(docs.length, 4);
      expect(
        [for (final d in docs) d['id']],
        containsAll(['press__1', 'press__2', 'press__3', 'press__4']),
      );

      final s = (c.read(wearSessionProvider) as WearSessionRunning).session;
      expect(s.isFullyCompleted, isTrue);
    });

    // Ojo con lo que prueba: el documento único lo garantiza el id
    // DETERMINÍSTICO —dos toques escriben la misma ruta—, no el guard de
    // `pending`. Se comprobó mutando: sacar el guard deja este test en verde.
    // El guard igual se queda, pero su valor es otro: evita el viaje de red
    // redundante, y en una muñeca el doble toque es frecuente.
    test('dos toques sobre la misma serie dejan UN documento', () async {
      final c = contenedor();
      final corriendo = await arrancado(c);
      final n = c.read(wearSessionProvider.notifier);

      await Future.wait([
        n.logSet(exerciseId: 'press', setNumber: 1),
        n.logSet(exerciseId: 'press', setNumber: 1),
      ]);
      await pumpEventQueue();

      expect((await docsDeSeries(corriendo.session.sessionId)).length, 1);
    });

    test('con un rango se registra el MÁXIMO, igual que watchOS', () async {
      final c = contenedor();
      final corriendo = await arrancado(c);
      await c
          .read(wearSessionProvider.notifier)
          .logSet(exerciseId: 'press', setNumber: 1);
      await pumpEventQueue();

      final docs = await docsDeSeries(corriendo.session.sessionId);
      // El slot es targetRepsMin 8 / targetRepsMax 12.
      expect(docs.single['reps'], 12);
    });

    test('una serie que no existe en el plan no escribe nada', () async {
      final c = contenedor();
      final corriendo = await arrancado(c);
      final n = c.read(wearSessionProvider.notifier);

      await n.logSet(exerciseId: 'press', setNumber: 99);
      await n.logSet(exerciseId: 'inventado', setNumber: 1);
      await pumpEventQueue();

      expect(await docsDeSeries(corriendo.session.sessionId), isEmpty);
    });
  });

  group('el nativo sigue el ciclo del ENTRENO, no el de la app', () {
    test('al abrir un entreno se limpia el descanso y arranca el servicio',
        () async {
      // El bug que reportó el dueño: abandonar y volver a empezar dejaba el
      // temporizador corriendo donde había quedado, con CERO series marcadas.
      // El deadline vive persistido en el nativo para sobrevivir a que se
      // destruya la Activity, así que hay que limpiarlo explícitamente.
      final c = contenedor();
      await pumpEventQueue();
      await c.read(wearSessionProvider.notifier).start(hoy);
      await pumpEventQueue();

      verify(() => nativo.cancelRest()).called(1);
      verify(() => nativo.startWorkout()).called(1);
    });

    test('al cerrarlo se apaga el servicio y se limpia el descanso', () async {
      // Y con el servicio se apaga ExerciseSessionController, que es lo que
      // cuenta pulso y calorías. Antes arrancaba con el EMPAREJAMIENTO y no
      // paraba nunca, así que las calorías no eran del entreno.
      final c = contenedor();
      await pumpEventQueue();
      await c.read(wearSessionProvider.notifier).start(hoy);
      await pumpEventQueue();
      await c.read(wearSessionProvider.notifier).abandon();
      await pumpEventQueue();

      verify(() => nativo.stopWorkout()).called(1);
      verify(() => nativo.cancelRest()).called(2);
    });

    test('adoptar un entreno abierto también prepara el nativo', () async {
      await repo.create(
        uid: uid,
        routineId: 'r1',
        routineName: 'Fuerza Base',
        startedAt: DateTime.utc(2026, 8, 18, 9),
        dayNumber: 2,
        weekNumber: 0,
      );

      final c = contenedor();
      await pumpEventQueue();

      expect(c.read(wearSessionProvider), isA<WearSessionRunning>());
      verify(() => nativo.startWorkout()).called(1);
    });
  });

  test('lo que está en vuelo lo drena el historial, no el await', () async {
    // Vino de un bug que vio el dueño con el cartel de «sin subir» —iba a 1, 2,
    // 3 y no bajaba— y sobrevive al cartel, que ya se sacó: `pending` sigue
    // siendo lo que llena el círculo en el toque, y si no drenara, un círculo
    // marcado por una escritura que falló quedaría verde para siempre.
    //
    // `set()` de Firestore no completa hasta que el servidor confirma, así que
    // sin red el `finally` NO corre. Se simula con una escritura que no vuelve.
    final colgada = Completer<SetLog?>();
    final repoLento = _RepoQueNoVuelve(repo, colgada.future);

    final c = ProviderContainer(
      overrides: [
        currentUidProvider.overrideWithValue(uid),
        sessionRepositoryProvider.overrideWithValue(repoLento),
        routineByIdProvider.overrideWith((ref, id) async => rutina),
        wearWorkoutServiceProvider.overrideWithValue(nativo),
      ],
    );
    addTearDown(c.dispose);
    c.listen(wearSessionProvider, (_, __) {});
    await pumpEventQueue();

    await c.read(wearSessionProvider.notifier).start(hoy);
    await pumpEventQueue();
    final sid =
        (c.read(wearSessionProvider) as WearSessionRunning).session.sessionId;

    unawaited(
      c.read(wearSessionProvider.notifier).logSet(
            exerciseId: 'press',
            setNumber: 1,
          ),
    );
    await pumpEventQueue();

    // En vuelo: el círculo ya se llenó, y el cartel lo dice.
    expect(
      (c.read(wearSessionProvider) as WearSessionRunning).session.pending,
      {'press__1'},
    );

    // La serie aparece en el historial —la escritura local se aplicó al caché—
    // aunque la promesa del servidor siga colgada.
    await repo.addSetLogFromWatch(
      uid: uid,
      sessionId: sid,
      setLog: SetLog(
        id: '',
        exerciseId: 'press',
        exerciseName: 'press',
        setNumber: 1,
        reps: 6,
        weightKg: 80,
        completedAt: DateTime.utc(2026, 8, 18, 10),
      ),
    );
    await pumpEventQueue();

    final s = (c.read(wearSessionProvider) as WearSessionRunning).session;
    expect(s.pending, isEmpty, reason: 'lo drena el historial, no el await');
    // El día 1 de la rutina de prueba tiene UN ejercicio.
    expect(s.loggedSets, [1]);
  });

  group('cerrar el entreno', () {
    test('terminar lo marca completo y vuelve a HOY', () async {
      final c = contenedor();
      await pumpEventQueue();
      await c.read(wearSessionProvider.notifier).start(hoy);
      await pumpEventQueue();

      final n = c.read(wearSessionProvider.notifier);
      for (var i = 1; i <= 4; i++) {
        await n.logSet(exerciseId: 'press', setNumber: i);
      }
      await pumpEventQueue();
      await n.finish();
      await pumpEventQueue();

      expect(c.read(wearSessionProvider), isA<WearSessionIdle>());
      expect(await sesionesActivas(), 0);

      final snap = await firestore
          .collection('users')
          .doc(uid)
          .collection('sessions')
          .get();
      final doc = snap.docs.single.data();
      expect(doc['wasFullyCompleted'], isTrue);
      // 4 series de 12 reps x 0 kg (el slot no tiene peso objetivo).
      expect(doc['totalVolumeKg'], 0.0);
    });

    test('abandonar cierra sin marcarlo completo', () async {
      final c = contenedor();
      await pumpEventQueue();
      await c.read(wearSessionProvider.notifier).start(hoy);
      await pumpEventQueue();

      await c.read(wearSessionProvider.notifier).abandon();
      await pumpEventQueue();

      expect(c.read(wearSessionProvider), isA<WearSessionIdle>());
      final snap = await firestore
          .collection('users')
          .doc(uid)
          .collection('sessions')
          .get();
      expect(snap.docs.single.data()['wasFullyCompleted'], isFalse);
    });
  });

  test('el historial en vivo mueve el cursor', () async {
    final c = contenedor();
    await pumpEventQueue();
    await c.read(wearSessionProvider.notifier).start(hoy);
    await pumpEventQueue();

    final sessionId =
        (c.read(wearSessionProvider) as WearSessionRunning).session.sessionId;

    // Cuatro series del press llegan desde afuera (las marcó el teléfono).
    for (var n = 1; n <= 4; n++) {
      await repo.addSetLogFromWatch(
        uid: uid,
        sessionId: sessionId,
        setLog: SetLog(
          id: '',
          exerciseId: 'press',
          exerciseName: 'press',
          setNumber: n,
          reps: 10,
          weightKg: 60,
          completedAt: DateTime.utc(2026, 8, 18, 10, n),
        ),
      );
    }
    await pumpEventQueue();

    final s = (c.read(wearSessionProvider) as WearSessionRunning).session;
    expect(s.loggedSets, [4]);
    expect(s.isFullyCompleted, isTrue);
  });
}
