import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/workout/data/session_repository.dart';
import 'package:treino/features/workout/domain/rest_state.dart';

/// El descanso compartido, anotado en el doc de sesión (#1616).
///
/// Es el canal por el que el teléfono, el Wear OS y el Apple Watch ven EL
/// MISMO descanso. Lo que se prueba acá es que el documento alcance para
/// reconstruirlo entero del otro lado —cuánto falta, de qué serie, de quién— y
/// que saltarlo lo saque para todos.
void main() {
  late FakeFirebaseFirestore firestore;
  late SessionRepository repo;

  const uid = 'atleta-1';
  const sessionId = 'sesion-1';

  /// Instante fijo: un test que dependa de la fecha de hoy caduca.
  final arranque = DateTime.utc(2031, 3, 4, 18, 30);

  DocumentReference<Map<String, Object?>> doc() => firestore
      .collection('users')
      .doc(uid)
      .collection('sessions')
      .doc(sessionId);

  setUp(() async {
    firestore = FakeFirebaseFirestore();
    repo = SessionRepository(firestore: firestore);
    // La sesión existe: el descanso cuelga de ella.
    await doc().set({'status': 'active', 'routineId': 'r1'});
  });

  RestState descanso({
    RestOwner owner = RestOwner.telefono,
    int totalSeconds = 90,
  }) =>
      RestState.startedAt(
        exerciseId: 'press-banca',
        setNumber: 2,
        totalSeconds: totalSeconds,
        start: arranque,
        owner: owner,
      );

  Future<RestState?> leer() =>
      repo.watchRest(uid: uid, sessionId: sessionId).first;

  group('lo que se anota es lo que el otro aparato reconstruye', () {
    test('un descanso del teléfono vuelve entero', () async {
      final escrito = descanso();
      await repo.writeRest(uid: uid, sessionId: sessionId, rest: escrito);

      expect(await leer(), escrito);
    });

    test('uno del reloj también, con su dueño', () async {
      final escrito = descanso(owner: RestOwner.reloj);
      await repo.writeRest(uid: uid, sessionId: sessionId, rest: escrito);

      final leido = await leer();
      expect(leido, escrito);
      expect(leido!.owner, RestOwner.reloj);
    });

    test('el fin viaja ABSOLUTO, en epoch de ms, y el dueño con valor propio',
        () async {
      final escrito = descanso(owner: RestOwner.reloj);
      await repo.writeRest(uid: uid, sessionId: sessionId, rest: escrito);

      final crudo = (await doc().get()).data()!;
      // Absoluto y no un offset: ronda 1,9e12 y NO entra en 32 bits, que es
      // la presión que documenta `conformance/rest_timer.json` para el reloj.
      expect(
        crudo[SessionRepository.fieldRestEndsAt],
        escrito.endsAt.millisecondsSinceEpoch,
      );
      expect(crudo[SessionRepository.fieldRestEndsAt], greaterThan(1e12));
      // El mismo literal que lee el Apple Watch por REST: renombrar el enum en
      // Dart no puede cambiar lo que ya está escrito.
      expect(
        crudo[SessionRepository.fieldRestOwner],
        SessionRepository.ownerWatch,
      );
    });

    test('+15 s reescribe el MISMO descanso, más largo', () async {
      final original = descanso();
      await repo.writeRest(uid: uid, sessionId: sessionId, rest: original);

      final estirado = original.extendedBy(15, now: arranque)!;
      await repo.writeRest(uid: uid, sessionId: sessionId, rest: estirado);

      final leido = await leer();
      expect(leido!.totalSeconds, 105);
      expect(leido.endsAt, original.endsAt.add(const Duration(seconds: 15)));
      expect(leido.exerciseId, original.exerciseId,
          reason: 'estirarlo no lo vuelve otro descanso');
    });
  });

  group('SALTAR lo saca para todos', () {
    test('borrarlo deja la sesión sin descanso', () async {
      await repo.writeRest(uid: uid, sessionId: sessionId, rest: descanso());
      await repo.clearRest(uid: uid, sessionId: sessionId);

      expect(await leer(), isNull);
      final crudo = (await doc().get()).data()!;
      expect(
        crudo.keys.where((k) => k.startsWith('rest')),
        isEmpty,
        reason: 'no puede quedar medio descanso en el documento',
      );
    });

    test('y no toca nada más de la sesión', () async {
      // Control negativo: borrar el descanso no puede llevarse la sesión.
      await repo.writeRest(uid: uid, sessionId: sessionId, rest: descanso());
      await repo.clearRest(uid: uid, sessionId: sessionId);

      final crudo = (await doc().get()).data()!;
      expect(crudo['status'], 'active');
      expect(crudo['routineId'], 'r1');
    });
  });

  group('no inventa sesiones', () {
    test('sobre una sesión que no existe, la escritura falla', () async {
      // `update` y no `set(merge)`: una sesión borrada en el medio no puede
      // renacer como un documento que sólo tiene el descanso.
      await doc().delete();

      await expectLater(
        repo.writeRest(uid: uid, sessionId: sessionId, rest: descanso()),
        throwsA(anything),
      );
      expect((await doc().get()).exists, isFalse);
    });
  });

  group('medio descanso no se espeja', () {
    for (final campo in [
      SessionRepository.fieldRestExerciseId,
      SessionRepository.fieldRestSetNumber,
      SessionRepository.fieldRestTotalSeconds,
      SessionRepository.fieldRestEndsAt,
      SessionRepository.fieldRestOwner,
    ]) {
      test('sin $campo se lee como "no hay"', () async {
        await repo.writeRest(
          uid: uid,
          sessionId: sessionId,
          rest: descanso(),
        );
        await doc().update({campo: FieldValue.delete()});

        expect(await leer(), isNull);
      });
    }
  });

  test('un cambio ajeno al descanso no vuelve a emitir', () async {
    // El doc de sesión cambia por muchas otras cosas —el cronómetro, el
    // cierre—, y cada espejo tiene que reaccionar sólo a su descanso: si no,
    // el Wear OS releería el nativo en cada cambio del documento.
    final emitidos = <RestState?>[];
    final sub =
        repo.watchRest(uid: uid, sessionId: sessionId).listen(emitidos.add);
    addTearDown(sub.cancel);

    await repo.writeRest(uid: uid, sessionId: sessionId, rest: descanso());
    await pumpEventQueue();
    final antes = emitidos.length;

    await doc().update({'timerOwner': 'phone'});
    await pumpEventQueue();

    expect(emitidos.length, antes);
  });
}
