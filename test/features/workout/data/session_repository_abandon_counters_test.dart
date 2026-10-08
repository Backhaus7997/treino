import 'package:cloud_firestore/cloud_firestore.dart'
    show FirebaseException, Timestamp;
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:mock_exceptions/mock_exceptions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/profile/data/user_public_profile_repository.dart';
import 'package:treino/features/workout/data/session_repository.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late UserPublicProfileRepository publicProfileRepo;
  late SessionRepository repo;

  const uid = 'user-abandon-001';
  const routineId = 'routine-ppl';
  const routineName = 'Push Pull Legs';

  setUp(() {
    firestore = FakeFirebaseFirestore();
    publicProfileRepo = UserPublicProfileRepository(firestore: firestore);
    repo = SessionRepository(
      firestore: firestore,
      publicProfileRepository: publicProfileRepo,
    );
  });

  // BUGFIX: abandoned sessions (status=finished, wasFullyCompleted=false) must
  // NOT inflate the public workoutsCount/rachaSemanas counters. Only sessions with
  // wasFullyCompleted=true count, matching the display filter in
  // historial_section.dart and planProgressProvider.
  test(
      'abandoned session (wasFullyCompleted=false) does not increment public workoutsCount',
      () async {
    final session = await repo.create(
      uid: uid,
      routineId: routineId,
      routineName: routineName,
      startedAt: DateTime.utc(2026, 5, 15, 8, 0, 0),
    );

    // Abandon: finish() is called with wasFullyCompleted defaulting to false.
    await repo.finish(
      uid: uid,
      sessionId: session.id,
      finishedAt: DateTime.utc(2026, 5, 15, 8, 5, 0),
      totalVolumeKg: 0.0,
      durationMin: 0,
      wasFullyCompleted: false,
      weeklyTarget: 1,
    );

    final profileSnap =
        await firestore.collection('userPublicProfiles').doc(uid).get();
    expect(profileSnap.exists, isTrue);
    final data = profileSnap.data()!;
    // Abandoned session must NOT count as a workout.
    expect(data['workoutsCount'], equals(0));
    // La sesión abandonada no puede hacer que la semana cumpla el objetivo,
    // así que `finish` ni siquiera escribe el campo — la racha del atleta
    // queda intacta en vez de pisarse con un valor recalculado.
    expect(data.containsKey('rachaSemanas'), isFalse);
  });

  test(
      'only fully completed sessions are counted when mixed with abandoned ones',
      () async {
    // One completed session.
    final completed = await repo.create(
      uid: uid,
      routineId: routineId,
      routineName: routineName,
      startedAt: DateTime.utc(2026, 5, 15, 8, 0, 0),
    );
    await repo.finish(
      uid: uid,
      sessionId: completed.id,
      finishedAt: DateTime.utc(2026, 5, 15, 9, 0, 0),
      totalVolumeKg: 100.0,
      durationMin: 60,
      wasFullyCompleted: true,
      weeklyTarget: 1,
    );

    // One abandoned session.
    final abandoned = await repo.create(
      uid: uid,
      routineId: routineId,
      routineName: routineName,
      startedAt: DateTime.utc(2026, 5, 16, 8, 0, 0),
    );
    await repo.finish(
      uid: uid,
      sessionId: abandoned.id,
      finishedAt: DateTime.utc(2026, 5, 16, 8, 3, 0),
      totalVolumeKg: 0.0,
      durationMin: 0,
      wasFullyCompleted: false,
      weeklyTarget: 1,
    );

    final profileSnap =
        await firestore.collection('userPublicProfiles').doc(uid).get();
    final data = profileSnap.data()!;
    // Only the 1 fully completed session counts.
    expect(data['workoutsCount'], equals(1));
  });

  test(
      'con waitForServer:false los contadores SE SIGUEN escribiendo (es como '
      'los pasa el teléfono, siempre)', () async {
    // Este test existe por un bug que casi entra a main.
    //
    // Una versión de `finish` salteaba el recálculo cuando `waitForServer` era
    // false, razonando que «el contador queda viejo hasta el próximo cierre
    // con conexión». El razonamiento tenía un agujero: `waitForServer: false`
    // NO significa «estoy sin red», significa «no me bloquees», y el teléfono
    // lo pasa SIEMPRE. Los únicos callers con el default `true` son el
    // descarte del Home y el reloj, así que ese «próximo cierre» no existía y
    // los contadores dejaban de escribirse para siempre.
    //
    // Y no habría sido un número viejo: `effectiveRachaSemanas` hace decay EN
    // LECTURA contra `rachaSemanasUpdatedAt`, el sello que estampa
    // `updateCounters`. Sin sello nuevo, a las dos semanas todo atleta que
    // cierre desde el teléfono aparece con racha 0 mientras entrena todos los
    // días. El servidor no lo salva: `workoutsCount`/`rachaSemanas` no se
    // tocan en `functions/src/`.
    //
    // Ninguno de los otros tests de este archivo lo habría visto: todos usan
    // el default `true`, que es justamente el camino que el teléfono ya no
    // toma.
    final s1 = await repo.create(
      uid: uid,
      routineId: routineId,
      routineName: routineName,
      startedAt: DateTime.utc(2026, 5, 15, 8, 0, 0),
      waitForServer: false,
    );
    await repo.finish(
      uid: uid,
      sessionId: s1.id,
      finishedAt: DateTime.utc(2026, 5, 15, 9, 0, 0),
      totalVolumeKg: 100.0,
      durationMin: 60,
      wasFullyCompleted: true,
      weeklyTarget: 1,
      waitForServer: false,
    );

    // Se espera el RESULTADO, no una cantidad de turnos del event loop.
    //
    // La primera versión ponía dos `await Future.delayed(Duration.zero)`. Hoy
    // alcanzan —cada uno drena la cola entera de microtasks— pero es un número
    // sintonizado, no un principio: se rompe en silencio el día que el fake
    // cambie por dentro o que alguien agregue un hop a la cadena (un
    // `.timeout()`, un retry adentro de `updateCounters`). Y falla feo: un
    // `Actual: <null>` que no distingue «no se escribió» de «todavía no llegó».
    await firestore
        .collection('userPublicProfiles')
        .doc(uid)
        .snapshots()
        .firstWhere((snap) => snap.data()?['workoutsCount'] == 1)
        .timeout(
          const Duration(seconds: 5),
          onTimeout: () => throw StateError(
            'los contadores no se escribieron. Sin esto, cerrar un entreno '
            'desde el teléfono deja de actualizar el perfil público PARA '
            'SIEMPRE, y la racha decae a 0 en dos semanas.',
          ),
        );
  });

  test(
      'el recálculo CUELGA del ACK: si el servidor rechaza el cierre, los '
      'contadores no se tocan', () async {
    // Este test guarda el DISEÑO, no sólo el resultado, y hace falta porque el
    // de arriba no lo cubría: con `fake_cloud_firestore` el ACK resuelve al
    // instante, así que colgar el recálculo del ACK y dispararlo suelto son
    // indistinguibles. Medido — reemplazando la cadena por un `unawaited`
    // directo, aquel test seguía en verde.
    //
    // Lo que se protege es la razón de ser del fix: el recálculo lee las
    // sesiones recientes, y leerlas ANTES de que el servidor confirme
    // significa leer el caché, que puede estar incompleto y escribir un
    // `workoutsCount` más chico PISANDO el correcto del perfil público.
    const sessionId = 'session-cierre-rechazado';
    final sessionRef = firestore
        .collection('users')
        .doc(uid)
        .collection('sessions')
        .doc(sessionId);
    await sessionRef.set({
      'id': sessionId,
      'uid': uid,
      'routineId': routineId,
      'routineName': routineName,
      'startedAt': Timestamp.fromDate(DateTime.utc(2026, 5, 15, 8)),
      'finishedAt': null,
      'totalVolumeKg': 0.0,
      'durationMin': 0,
      'status': 'active',
      'dayNumber': 1,
      'weekNumber': 0,
      'wasFullyCompleted': false,
    });

    whenCalling(Invocation.method(#update, null)).on(sessionRef).thenThrow(
          FirebaseException(
            plugin: 'cloud_firestore',
            code: 'permission-denied',
            message: 'denied',
          ),
        );

    await repo.finish(
      uid: uid,
      sessionId: sessionId,
      finishedAt: DateTime.utc(2026, 5, 15, 9),
      totalVolumeKg: 100.0,
      durationMin: 60,
      wasFullyCompleted: true,
      weeklyTarget: 1,
      waitForServer: false,
    );
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    final snap =
        await firestore.collection('userPublicProfiles').doc(uid).get();
    expect(
      snap.data()?['workoutsCount'],
      isNull,
      reason: 'el servidor rechazó el cierre, así que no hay sesión terminada '
          'que contar. Si el recálculo dejara de colgar del ACK, escribiría un '
          'contador derivado de una lectura sin confirmar.',
    );
  });
}
