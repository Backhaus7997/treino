import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/core/utils/app_clock.dart';
import 'package:treino/features/watch/application/wear_rest_sync_providers.dart';
import 'package:treino/features/watch/data/wear_workout_service.dart';
import 'package:treino/features/workout/data/session_repository.dart';
import 'package:treino/features/workout/domain/rest_state.dart';

class _ServicioFalso extends Mock implements WearWorkoutService {}

/// Lo que toca el atleta en el Wear OS, anotado en la sesión (#1616).
///
/// El descanso NATIVO arranca siempre —es el que vibra aunque Dart duerma—, y
/// la sesión es el espejo que lo lleva al teléfono. Lo que no puede pasar es
/// que el espejo frene a la muñeca: sin sesión o sin red, el reloj descansa
/// solo, como antes.
void main() {
  late _ServicioFalso service;
  late FakeFirebaseFirestore firestore;
  late SessionRepository repo;

  const uid = 'atleta-1';
  const sessionId = 'sesion-1';

  DocumentReference<Map<String, Object?>> doc() => firestore
      .collection('users')
      .doc(uid)
      .collection('sessions')
      .doc(sessionId);

  setUp(() async {
    AppClock.freeze(DateTime(2026, 3, 17, 10, 30));
    addTearDown(AppClock.unfreeze);
    service = _ServicioFalso();
    when(() => service.startRest(any())).thenAnswer((_) async {});
    when(service.cancelRest).thenAnswer((_) async {});
    firestore = FakeFirebaseFirestore();
    repo = SessionRepository(firestore: firestore);
    await doc().set({'status': 'active'});
  });

  WearRestSync sync({String? sesion = sessionId}) => WearRestSync(
        service: service,
        repo: repo,
        uid: uid,
        sessionId: sesion,
      );

  Future<RestState?> enLaSesion() async {
    await pumpEventQueue();
    return SessionRepository.restFromDoc((await doc().get()).data());
  }

  test('marcar una serie arranca el nativo y lo anota, con el reloj de dueño',
      () async {
    await sync().arrancar(exerciseId: 'sentadilla', setNumber: 3, seconds: 120);

    verify(() => service.startRest(120)).called(1);
    final anotado = await enLaSesion();
    expect(anotado, isNotNull, reason: 'sin esto el teléfono nunca se entera');
    expect(anotado!.owner, RestOwner.reloj);
    expect(anotado.exerciseId, 'sentadilla');
    expect(anotado.setNumber, 3);
    expect(anotado.totalSeconds, 120);
    // El instante de fin es el del reloj de pared de ESTE aparato: el teléfono
    // cuenta contra el mismo y llegan a cero juntos.
    expect(
      anotado.endsAt,
      AppClock.now().toUtc().add(const Duration(seconds: 120)),
    );
  });

  test('SALTAR corta el nativo y lo borra de la sesión', () async {
    await sync().arrancar(exerciseId: 'sentadilla', setNumber: 3, seconds: 120);
    await sync().saltar();

    verify(service.cancelRest).called(1);
    expect(await enLaSesion(), isNull);
  });

  test('una serie sin descanso es SALTAR, también para el teléfono', () async {
    // El atleta ya volvió a entrenar: el descanso que venía corriendo se
    // corta en la muñeca Y en el teléfono. Antes el reloj lo cortaba solo acá.
    await sync().arrancar(exerciseId: 'sentadilla', setNumber: 3, seconds: 120);
    await sync().arrancar(exerciseId: 'plancha', setNumber: 1, seconds: 0);

    verify(service.cancelRest).called(1);
    verifyNever(() => service.startRest(0));
    expect(await enLaSesion(), isNull);
  });

  test('sin sesión en curso el reloj descansa solo, sin escribir nada',
      () async {
    // Control negativo: el espejo no puede ser requisito del descanso.
    await sync(sesion: null)
        .arrancar(exerciseId: 'sentadilla', setNumber: 3, seconds: 120);

    verify(() => service.startRest(120)).called(1);
    expect(await enLaSesion(), isNull);
  });

  test('si la escritura falla, el descanso nativo sigue en pie', () async {
    // La sesión se borró en el medio: `update` falla en vez de hacerla
    // renacer. La muñeca no se entera — su descanso ya arrancó.
    await doc().delete();

    await sync().arrancar(exerciseId: 'sentadilla', setNumber: 3, seconds: 120);
    await pumpEventQueue();

    verify(() => service.startRest(120)).called(1);
    expect((await doc().get()).exists, isFalse,
        reason: 'la sesión borrada no puede renacer con sólo el descanso');
  });
}
