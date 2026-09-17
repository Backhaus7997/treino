import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
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

    // El recálculo cuelga del ACK de la escritura, no del `await` de `finish`.
    // Con el fake el ACK resuelve en microtasks, así que alcanza con dejar
    // drenar la cola. En producción ocurre cuando vuelve la red.
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    final profileSnap =
        await firestore.collection('userPublicProfiles').doc(uid).get();
    expect(
      profileSnap.data()?['workoutsCount'],
      equals(1),
      reason:
          'sin esto, cerrar un entreno desde el teléfono deja de actualizar '
          'el perfil público PARA SIEMPRE, y la racha decae a 0 en dos semanas.',
    );
  });
}
