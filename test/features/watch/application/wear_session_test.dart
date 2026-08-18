import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/profile/domain/experience_level.dart';
import 'package:treino/features/watch/application/wear_session_providers.dart';
import 'package:treino/features/watch/presentation/wear/wear_view_models.dart';
import 'package:treino/features/workout/application/routine_providers.dart';
import 'package:treino/features/workout/application/session_providers.dart';
import 'package:treino/features/workout/data/session_repository.dart';
import 'package:treino/features/workout/domain/routine.dart';
import 'package:treino/features/workout/domain/routine_day.dart';
import 'package:treino/features/workout/domain/routine_slot.dart';
import 'package:treino/features/workout/domain/set_log.dart';

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

  setUp(() {
    firestore = FakeFirebaseFirestore();
    repo = SessionRepository(firestore: firestore);
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
