import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/workout/data/session_repository.dart';
import 'package:treino/features/workout/domain/duration_timer_owner.dart';
import 'package:treino/features/workout/domain/duration_timer_state.dart';

/// El cronómetro de la serie por tiempo, anotado en el doc de sesión.
///
/// Es el ÚNICO canal que cruza hacia un reloj de Wear OS: su Data Layer exige
/// emparejamiento con ese teléfono —medido en hardware— y además un mensaje se
/// pierde si el otro aparato no está escuchando. Lo que se prueba acá es que el
/// documento alcance para reconstruir la cuenta ENTERA del otro lado: cuánto
/// falta, en qué fila va, y —lo que un mensaje no necesitaba— DE QUIÉN es.
void main() {
  late FakeFirebaseFirestore firestore;
  late SessionRepository repo;

  const uid = 'atleta-1';
  const sessionId = 'sesion-1';

  /// Instante fijo: un test que dependa de la fecha de hoy caduca.
  final arranque = DateTime.utc(2031, 3, 4, 18, 30);

  setUp(() {
    firestore = FakeFirebaseFirestore();
    repo = SessionRepository(firestore: firestore);
  });

  /// El documento de sesión crudo, para mirar lo que realmente quedó escrito.
  ///
  /// Una función y no un getter: adentro de `main()` un getter no existe, y
  /// `firestore` se rehace en cada `setUp`.
  DocumentReference<Map<String, Object?>> doc() => firestore
      .collection('users')
      .doc(uid)
      .collection('sessions')
      .doc(sessionId);

  DurationTimerState arrancada({
    String exerciseId = 'plancha',
    int setNumber = 2,
    int totalSeconds = 60,
    required DurationTimerOwner owner,
  }) =>
      DurationTimerState.startedAt(
        exerciseId: exerciseId,
        setNumber: setNumber,
        totalSeconds: totalSeconds,
        start: arranque,
        owner: owner,
      );

  Future<DurationTimerState?> leer() =>
      repo.watchExerciseTimer(uid: uid, sessionId: sessionId).first;

  group('lo que se anota es lo que el otro aparato reconstruye', () {
    test('un cronómetro del teléfono vuelve entero, con su dueño', () async {
      final escrito = arrancada(owner: DurationTimerOwner.telefono);
      await repo.startExerciseTimer(
        uid: uid,
        sessionId: sessionId,
        timer: escrito,
      );

      expect(await leer(), escrito);
    });

    test('uno del reloj también, y se distingue del otro', () async {
      final escrito = arrancada(owner: DurationTimerOwner.reloj);
      await repo.startExerciseTimer(
        uid: uid,
        sessionId: sessionId,
        timer: escrito,
      );

      final leido = await leer();
      expect(leido, escrito);
      // El dueño es lo único que este shape tiene de más respecto del mensaje
      // que va al reloj de Apple, y es lo que evita que los dos carguen la
      // misma serie. Si viajara mal, el bug volvería sin ningún síntoma.
      expect(leido!.owner, DurationTimerOwner.reloj);
    });

    test('el instante de fin viaja ABSOLUTO, en epoch de milisegundos',
        () async {
      final escrito = arrancada(
        totalSeconds: 60,
        owner: DurationTimerOwner.telefono,
      );
      await repo.startExerciseTimer(
        uid: uid,
        sessionId: sessionId,
        timer: escrito,
      );

      final crudo = (await doc().get()).data()!;
      // Absoluto y no un offset: ronda 1,8e12 y NO entra en 32 bits, que es la
      // presión que `conformance/duration_timer.json` documenta para el reloj.
      expect(
        crudo[SessionRepository.fieldTimerEndsAt],
        escrito.endsAt.millisecondsSinceEpoch,
      );
      expect(crudo[SessionRepository.fieldTimerEndsAt], greaterThan(1e12));
    });

    test('el dueño se escribe con un valor propio, no con el nombre del enum',
        () async {
      await repo.startExerciseTimer(
        uid: uid,
        sessionId: sessionId,
        timer: arrancada(owner: DurationTimerOwner.reloj),
      );

      // Renombrar el enum en Dart no puede cambiar lo que ya está escrito en
      // una sesión viva: si el valor dejara de reconocerse, el espejo se
      // creería dueño y cargaría la serie por segunda vez.
      expect(
        (await doc().get()).data()![SessionRepository.fieldTimerOwner],
        SessionRepository.ownerWatch,
      );
    });
  });

  group('borrar lo deja en NADA, no en medio cronómetro', () {
    test('después de borrar no hay cronómetro', () async {
      await repo.startExerciseTimer(
        uid: uid,
        sessionId: sessionId,
        timer: arrancada(owner: DurationTimerOwner.telefono),
      );
      await repo.clearExerciseTimer(uid: uid, sessionId: sessionId);

      expect(await leer(), isNull);
    });

    test('no queda ningún campo del cronómetro suelto', () async {
      await repo.startExerciseTimer(
        uid: uid,
        sessionId: sessionId,
        timer: arrancada(owner: DurationTimerOwner.telefono),
      );
      await repo.clearExerciseTimer(uid: uid, sessionId: sessionId);

      // Un campo huérfano no rompe la lectura —falta el resto— pero deja basura
      // que la próxima serie tendría que pisar entera.
      final crudo = (await doc().get()).data() ?? {};
      for (final campo in [
        SessionRepository.fieldTimerExerciseId,
        SessionRepository.fieldTimerSetNumber,
        SessionRepository.fieldTimerTotalSeconds,
        SessionRepository.fieldTimerEndsAt,
        SessionRepository.fieldTimerOwner,
      ]) {
        expect(crudo.containsKey(campo), isFalse, reason: campo);
      }
    });

    test('no toca el resto de la sesión', () async {
      await doc().set({'routineId': 'r1'});
      await repo.startExerciseTimer(
        uid: uid,
        sessionId: sessionId,
        timer: arrancada(owner: DurationTimerOwner.telefono),
      );
      await repo.clearExerciseTimer(uid: uid, sessionId: sessionId);

      expect((await doc().get()).data()!['routineId'], 'r1');
    });
  });

  group('un documento incompleto se lee como NADA', () {
    // Media cuenta no se puede ubicar en una fila ni se le puede saber el
    // dueño, y un espejo sin dueño se cree dueño: cargaría la serie el que
    // sólo tenía que mirarla.
    Future<void> sembrar(Map<String, Object?> campos) => doc().set(campos);

    test('sin dueño no hay cronómetro', () async {
      await sembrar({
        SessionRepository.fieldTimerExerciseId: 'plancha',
        SessionRepository.fieldTimerSetNumber: 2,
        SessionRepository.fieldTimerTotalSeconds: 60,
        SessionRepository.fieldTimerEndsAt:
            arranque.millisecondsSinceEpoch + 60000,
      });

      expect(await leer(), isNull);
    });

    test('con un dueño que no se reconoce tampoco', () async {
      await sembrar({
        SessionRepository.fieldTimerExerciseId: 'plancha',
        SessionRepository.fieldTimerSetNumber: 2,
        SessionRepository.fieldTimerTotalSeconds: 60,
        SessionRepository.fieldTimerEndsAt:
            arranque.millisecondsSinceEpoch + 60000,
        SessionRepository.fieldTimerOwner: 'heladera',
      });

      expect(await leer(), isNull);
    });

    test('sin identidad tampoco', () async {
      await sembrar({
        SessionRepository.fieldTimerTotalSeconds: 60,
        SessionRepository.fieldTimerEndsAt:
            arranque.millisecondsSinceEpoch + 60000,
        SessionRepository.fieldTimerOwner: SessionRepository.ownerPhone,
      });

      expect(await leer(), isNull);
    });

    test('una sesión sin nada del cronómetro da null y no rompe', () async {
      await sembrar({'routineId': 'r1'});

      expect(await leer(), isNull);
    });
  });

  group('no se escribe lo que no es un cronómetro', () {
    test('una duración en cero no se anota', () async {
      await repo.startExerciseTimer(
        uid: uid,
        sessionId: sessionId,
        timer: DurationTimerState(
          exerciseId: 'plancha',
          setNumber: 2,
          totalSeconds: 0,
          endsAt: arranque,
          owner: DurationTimerOwner.telefono,
        ),
      );

      expect(await leer(), isNull);
    });

    test('un cronómetro de NADIE no se anota', () async {
      // `nadie` es la ausencia de cronómetro, y la ausencia se representa con
      // la ausencia del documento — no con un documento que dice "de nadie",
      // que el otro lado tendría que aprender a ignorar.
      await repo.startExerciseTimer(
        uid: uid,
        sessionId: sessionId,
        timer: DurationTimerState(
          exerciseId: 'plancha',
          setNumber: 2,
          totalSeconds: 60,
          endsAt: arranque.add(const Duration(seconds: 60)),
          owner: DurationTimerOwner.nadie,
        ),
      );

      expect(await leer(), isNull);
    });
  });
}
