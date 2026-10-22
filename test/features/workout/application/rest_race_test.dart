import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/core/utils/app_clock.dart';
import 'package:treino/features/watch/application/wear_rest_sync_providers.dart';
import 'package:treino/features/watch/data/wear_workout_service.dart';
import 'package:treino/features/workout/data/session_repository.dart';
import 'package:treino/features/workout/domain/rest_rules.dart';
import 'package:treino/features/workout/domain/rest_state.dart';

class _NativoFalso extends Mock implements WearWorkoutService {}

/// La carrera: el atleta marca en el teléfono y en el reloj casi a la vez
/// (#1616).
///
/// La regla elegida es **gana el que escribe último**: el descanso es un
/// registro único en la sesión y espejar nunca escribe, así que los aparatos
/// convergen al último valor que aceptó el servidor. El que escribió primero
/// adopta el del otro; el que escribió último no toca nada. Los dos terminan
/// contando contra EL MISMO instante de fin — que es lo único que el atleta
/// necesita para que avisen juntos.
///
/// El teléfono decide con [RestRules.decide], que es exactamente lo que llama
/// `SessionPlayerScreen._onDescansoRemoto`; el Wear, con su buzón real.
void main() {
  const uid = 'atleta-1';
  const sessionId = 'sesion-1';

  late FakeFirebaseFirestore firestore;
  late SessionRepository repo;
  late _NativoFalso nativo;

  /// Lo que falta en el descanso nativo del Wear, en ms. Null = no hay.
  int? nativoFaltaMs;

  /// El instante en que marca el primero. El segundo marca 1,2 s después:
  /// más que la tolerancia, así que son de verdad dos descansos distintos.
  final t0 = DateTime(2026, 3, 17, 10, 30);
  const desfase = Duration(milliseconds: 1200);

  setUpAll(() => registerFallbackValue(Duration.zero));

  setUp(() async {
    firestore = FakeFirebaseFirestore();
    repo = SessionRepository(firestore: firestore);
    await firestore
        .collection('users')
        .doc(uid)
        .collection('sessions')
        .doc(sessionId)
        .set({'status': 'active'});

    nativoFaltaMs = null;
    nativo = _NativoFalso();
    // El nativo arranca con los SEGUNDOS que le pasa el reloj al marcar, o con
    // los ms del espejo. Se modela lo que falta, que es lo que lee el buzón.
    when(() => nativo.startRest(any())).thenAnswer((inv) async {
      nativoFaltaMs = (inv.positionalArguments.first as int) * 1000;
    });
    when(() => nativo.startRestFor(any())).thenAnswer((inv) async {
      nativoFaltaMs =
          (inv.positionalArguments.first as Duration).inMilliseconds;
    });
    when(nativo.cancelRest).thenAnswer((_) async => nativoFaltaMs = null);
    when(nativo.restState).thenAnswer(
      (_) async => nativoFaltaMs == null
          ? null
          : (
              endsAtElapsedMs: 0,
              remainingMs: nativoFaltaMs!,
              finished: nativoFaltaMs! <= 0,
            ),
    );
    addTearDown(AppClock.unfreeze);
  });

  /// El reloj de pared avanzó hasta [t]: el nativo descontó lo mismo.
  void pasarA(DateTime t, {required DateTime desde}) {
    AppClock.freeze(t);
    if (nativoFaltaMs != null) {
      nativoFaltaMs = nativoFaltaMs! - t.difference(desde).inMilliseconds;
    }
  }

  WearRestSync wear() => WearRestSync(
        service: nativo,
        repo: repo,
        uid: uid,
        sessionId: sessionId,
      );

  Future<RestState> enLaSesion() async {
    await pumpEventQueue();
    return (await repo.watchRest(uid: uid, sessionId: sessionId).first)!;
  }

  /// El instante de fin que cuenta el Wear, llevado a tiempo de pared.
  DateTime finDelWear() =>
      AppClock.now().toUtc().add(Duration(milliseconds: nativoFaltaMs ?? 0));

  test('marca el teléfono y después el reloj: gana el reloj', () async {
    AppClock.freeze(t0);
    final delTelefono = RestState.startedAt(
      exerciseId: 'press-banca',
      setNumber: 2,
      totalSeconds: 90,
      start: t0.toUtc(),
      owner: RestOwner.telefono,
    );
    await repo.writeRest(uid: uid, sessionId: sessionId, rest: delTelefono);

    pasarA(t0.add(desfase), desde: t0);
    await wear().arrancar(exerciseId: 'press-banca', setNumber: 2, seconds: 90);

    final ganador = await enLaSesion();
    expect(ganador.owner, RestOwner.reloj, reason: 'escribió último');

    // El teléfono escribió primero: adopta el del reloj.
    expect(
      RestRules.decide(
        local: delTelefono.endsAt,
        remote: ganador.endsAt,
        now: AppClock.now().toUtc(),
      ),
      RestMirrorAction.adopt,
    );

    // El reloj escribió último: su eco no reprograma nada.
    await espejarDescansoEnElReloj(nativo, ganador);
    verifyNever(() => nativo.startRestFor(any()));

    // Y los dos cuentan contra el MISMO fin.
    expect(finDelWear().difference(ganador.endsAt).abs(),
        lessThanOrEqualTo(RestRules.mirrorTolerance));
  });

  test('marca el reloj y después el teléfono: gana el teléfono', () async {
    AppClock.freeze(t0);
    await wear().arrancar(exerciseId: 'press-banca', setNumber: 2, seconds: 90);
    final delReloj = await enLaSesion();

    pasarA(t0.add(desfase), desde: t0);
    final delTelefono = RestState.startedAt(
      exerciseId: 'press-banca',
      setNumber: 2,
      totalSeconds: 90,
      start: AppClock.now().toUtc(),
      owner: RestOwner.telefono,
    );
    await repo.writeRest(uid: uid, sessionId: sessionId, rest: delTelefono);

    final ganador = await enLaSesion();
    expect(ganador, delTelefono, reason: 'escribió último');
    expect(ganador, isNot(delReloj));

    // El teléfono escribió último: no toca nada.
    expect(
      RestRules.decide(
        local: delTelefono.endsAt,
        remote: ganador.endsAt,
        now: AppClock.now().toUtc(),
      ),
      RestMirrorAction.keep,
    );

    // El reloj escribió primero: reprograma su alarma al fin del teléfono.
    await espejarDescansoEnElReloj(nativo, ganador);
    verify(() => nativo.startRestFor(any())).called(1);
    expect(finDelWear(), ganador.endsAt);
  });

  test('control: si nadie escribe después, el primero no cambia', () async {
    // Si nadie escribe después, el primero NO cambia: la regla no es "el
    // reloj gana" ni "el teléfono gana", es "el último gana".
    AppClock.freeze(t0);
    await wear().arrancar(exerciseId: 'press-banca', setNumber: 2, seconds: 90);
    final soloReloj = await enLaSesion();

    await espejarDescansoEnElReloj(nativo, soloReloj);

    verifyNever(() => nativo.startRestFor(any()));
    expect(soloReloj.owner, RestOwner.reloj);
  });
}
