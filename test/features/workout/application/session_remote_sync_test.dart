import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/workout/data/session_repository.dart';

/// El teléfono tiene que ver EN VIVO lo que el reloj escribe en la misma
/// sesión.
///
/// `SessionNotifier` sacaba una foto con `listSetLogs` al abrir el entreno y no
/// volvía a mirar. El atleta marcaba la serie en la muñeca y la pantalla del
/// celular seguía mostrándola sin tildar; y si terminaba desde el reloj, el
/// player quedaba vivo sobre una sesión ya cerrada.
///
/// Se prueba el REPOSITORIO y no el notifier a propósito: el notifier es un
/// `AutoDisposeFamilyAsyncNotifier` que necesita rutina, perfil y auth
/// montados, y el comportamiento que importa —que Firestore empuje los
/// cambios— vive en estos dos streams. Los tests del notifier ya cubren que
/// consume lo que el repo le da.
void main() {
  late FakeFirebaseFirestore firestore;
  late SessionRepository repo;

  const uid = 'atleta-1';
  const sessionId = 'sesion-1';

  Future<void> writeSet(String id, int setNumber) async {
    await firestore
        .collection('users')
        .doc(uid)
        .collection('sessions')
        .doc(sessionId)
        .collection('setLogs')
        .doc(id)
        .set({
      'id': id,
      'exerciseId': 'ex-1',
      'exerciseName': 'Sentadilla',
      'setNumber': setNumber,
      'reps': 6,
      'weightKg': 80.0,
      'completedAt': DateTime.utc(2026, 8, 10),
    });
  }

  setUp(() {
    firestore = FakeFirebaseFirestore();
    repo = SessionRepository(firestore: firestore);
  });

  test('watchSetLogs emite cuando el reloj escribe una serie nueva', () async {
    await writeSet('ex-1__1', 1);

    final emissions = repo.watchSetLogs(uid: uid, sessionId: sessionId);
    final first = await emissions.first;
    expect(first.length, 1);

    // El RELOJ escribe la segunda serie. Nadie invalida nada en el teléfono.
    final future = emissions.firstWhere((logs) => logs.length == 2);
    await writeSet('ex-1__2', 2);

    final updated = await future.timeout(const Duration(seconds: 5));
    expect(
      updated.map((l) => l.setNumber),
      containsAll(<int>[1, 2]),
      reason: 'sin el stream el telefono se quedaba con la foto inicial',
    );
  });

  test('watchSetLogs respeta el orden por setNumber', () async {
    await writeSet('ex-1__2', 2);
    await writeSet('ex-1__1', 1);
    final logs = await repo.watchSetLogs(uid: uid, sessionId: sessionId).first;
    // Mismo orden que `listSetLogs`: sin esto el estado daba un salto visual
    // al reemplazar la carga inicial por la del stream.
    expect(logs.map((l) => l.setNumber).toList(), <int>[1, 2]);
  });

  group('watchSessionFinished', () {
    Future<void> writeSession({DateTime? finishedAt}) async {
      await firestore
          .collection('users')
          .doc(uid)
          .collection('sessions')
          .doc(sessionId)
          .set({
        'id': sessionId,
        'uid': uid,
        'routineId': 'r1',
        'routineName': 'Rutina',
        'startedAt': DateTime.utc(2026, 8, 10),
        // La clave viaja SIEMPRE, con null cuando no terminó. Es la misma
        // trampa que rompió el lado del reloj: "ausente" y "nulo" no son lo
        // mismo, así que hay que mirar el VALOR.
        'finishedAt': finishedAt,
        'status': finishedAt == null ? 'active' : 'finished',
        'totalVolumeKg': 0.0,
        'durationMin': 0,
      });
    }

    test('una sesion abierta NO se reporta terminada', () async {
      await writeSession();
      expect(
        await repo.watchSessionFinished(uid: uid, sessionId: sessionId).first,
        isFalse,
        reason: 'finishedAt existe con valor null — mirar la clave no alcanza',
      );
    });

    test('emite true cuando el reloj la cierra', () async {
      await writeSession();
      final stream = repo.watchSessionFinished(uid: uid, sessionId: sessionId);
      final future = stream.firstWhere((finished) => finished);

      await writeSession(finishedAt: DateTime.utc(2026, 8, 10, 1));

      expect(await future.timeout(const Duration(seconds: 5)), isTrue);
    });

    test('una sesion que no existe cuenta como terminada', () async {
      // Seguir mostrando el player sobre un doc borrado es peor que cerrarlo.
      expect(
        await repo.watchSessionFinished(uid: uid, sessionId: 'no-existe').first,
        isTrue,
      );
    });
  });
}
