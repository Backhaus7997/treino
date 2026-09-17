// session_repository_adoption_timeout_test.dart — la lectura de adopción del
// reloj tiene fondo.
//
// ─── Por qué existe, y por qué NO va en session_repository_test ─────────────
//
// `addSetLog` abre con un `get()` del documento determinístico del reloj para
// adoptarlo si llegó primero. Esa lectura puede fallar de DOS maneras, y
// tolerar una no cubre la otra:
//
//   • TIRA — sin red y sin el documento en cache. Lo cubre el `try/catch`, y
//     lo prueba `session_repository_test.dart` con `mock_exceptions`.
//   • NO devuelve NI tira — la conexión queda a medias. Es el caso que este
//     repo MIDIÓ en el simulador el 2026-08-12 y documentó en
//     `network_timeouts.dart`: «no hay excepción, no hay log, no hay reintento
//     y no hay salida». Sin cota, `logSet` se queda esperando, su guard anti
//     doble-tap queda trabado en `true`, y vuelve el bug entero: no se puede
//     marcar ni una serie más en toda la sesión.
//
// El segundo caso no se puede montar con `FakeFirebaseFirestore`: sus
// operaciones siempre resuelven, y `mock_exceptions` sólo sabe TIRAR. De ahí
// este archivo aparte, con un doble mínimo de la cadena de Firestore cuyo
// `get()` no contesta nunca. Un `Completer` que nadie completa es la única
// forma honesta de escribir «la conexión quedó a medias».
//
// Lo señaló Codex en la review del PR, apoyándose en la documentación del
// propio repo. Yo había escrito en el cuerpo del PR que `get()` «cae al cache
// offline y resuelve, así que no cuelga». Eso lo razoné, no lo medí.

// `FirebaseFirestore`, `CollectionReference`, `DocumentReference` y
// `DocumentSnapshot` están `@sealed` en `cloud_firestore`, así que mockearlas
// dispara `subtype_of_sealed_class`. Es el mismo trato —y el mismo motivo— que
// en `trainer_link_repository_cache_fria_test.dart`: mockearlas es la ÚNICA
// forma de montar un `get()` que no contesta nunca, que es justo lo que este
// archivo prueba y lo que `fake_cloud_firestore` no puede modelar.
// ignore_for_file: subtype_of_sealed_class

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/core/utils/network_timeouts.dart';
import 'package:treino/features/workout/data/session_repository.dart';
import 'package:treino/features/workout/domain/set_log.dart';

class _MockFirestore extends Mock implements FirebaseFirestore {}

class _MockCollection extends Mock
    implements CollectionReference<Map<String, Object?>> {}

class _MockDoc extends Mock
    implements DocumentReference<Map<String, Object?>> {}

void main() {
  const uid = 'u1';
  const sessionId = 's1';
  const watchDocId = 'bench-press__1';

  late _MockFirestore firestore;
  late _MockDoc watchRef;
  late _MockDoc nuevoRef;
  late List<Map<String, Object?>> escrituras;

  SetLog serie() => SetLog(
        id: '',
        exerciseId: 'bench-press',
        exerciseName: 'Bench Press',
        setNumber: 1,
        reps: 10,
        weightKg: 80,
        rpe: null,
        completedAt: DateTime.utc(2026, 9, 17, 10),
      );

  setUp(() {
    firestore = _MockFirestore();
    watchRef = _MockDoc();
    nuevoRef = _MockDoc();
    escrituras = [];

    final users = _MockCollection();
    final userDoc = _MockDoc();
    final sessions = _MockCollection();
    final sessionDoc = _MockDoc();
    final setLogs = _MockCollection();

    when(() => firestore.collection('users')).thenReturn(users);
    when(() => users.doc(uid)).thenReturn(userDoc);
    when(() => userDoc.collection('sessions')).thenReturn(sessions);
    when(() => sessions.doc(sessionId)).thenReturn(sessionDoc);
    when(() => sessionDoc.collection('setLogs')).thenReturn(setLogs);

    // El documento del reloj: su lectura NO contesta jamás.
    when(() => setLogs.doc(watchDocId)).thenReturn(watchRef);
    when(() => watchRef.get()).thenAnswer(
      (_) => Completer<DocumentSnapshot<Map<String, Object?>>>().future,
    );

    // El documento propio, con id generado en el cliente.
    when(() => setLogs.doc()).thenReturn(nuevoRef);
    when(() => nuevoRef.id).thenReturn('id-autogenerado');
    when(() => nuevoRef.set(any())).thenAnswer((inv) async {
      escrituras.add(inv.positionalArguments[0] as Map<String, Object?>);
    });
  });

  test(
      'una lectura de adopción que no contesta NI falla no impide escribir la '
      'serie', () async {
    final repo = SessionRepository(
      firestore: firestore,
      // Bajada a milisegundos: un test que espera los 2 segundos reales no se
      // corre, y uno que no se corre no protege nada.
      watchAdoptionReadTimeout: const Duration(milliseconds: 20),
    );

    final logged = await repo
        .addSetLog(uid: uid, sessionId: sessionId, setLog: serie())
        // Si la cota no estuviera, esto se cuelga y el test falla por timeout
        // en vez de por la aserción — que es exactamente lo que le pasa al
        // atleta, sólo que a él nadie le corta a los 5 segundos.
        .timeout(const Duration(seconds: 5));

    expect(
      logged.setLog.id,
      'id-autogenerado',
      reason: 'si la adopción no contesta, la serie se escribe con id propio: '
          'el mismo camino que cuando el reloj no escribió nada.',
    );
    await logged.acknowledged;
    expect(
      escrituras,
      hasLength(1),
      reason: 'la serie que el atleta marcó tiene que quedar escrita aunque la '
          'lectura opcional de adopción se haya quedado colgada.',
    );
  });

  test('la cota NO se come una lectura que contesta a tiempo', () async {
    // Control del control: si la cota fuera tan agresiva que se comiera
    // siempre la adopción, el test de arriba pasaría por el motivo equivocado
    // y habríamos roto la deduplicación con el reloj sin enterarnos.
    //
    // ⚠️ EL DOBLE TIENE QUE CONSUMIR TIEMPO DE TIMER, no de microtask.
    //
    // La primera versión de este test stubeaba `thenAnswer((_) async => snap)`
    // y era INSERVIBLE: pasaba con `Duration.zero`, la cota más agresiva que
    // se puede escribir. Un `async` resuelve en la cola de MICROTASKS y
    // `Future.timeout` está implementado con un `Timer`; Dart drena todas las
    // microtasks antes de correr cualquier timer, así que el timer no gana
    // nunca — para NINGUNA duración. El test no medía la cota: medía que el
    // código adopta cuando la lectura es instantánea, que es otra cosa.
    //
    // `Future.delayed` sí es un Timer, así que compite en la misma cola.
    // Medido en los dos sentidos: con la cota de 20 ms va verde; con
    // `Duration.zero` va rojo.
    //
    // La regla general, que vale para cualquier `.timeout()` de este repo: si
    // el control es sobre la EXISTENCIA de la cota, un `Completer` eterno
    // alcanza (test de arriba). Si es sobre su MAGNITUD, el doble tiene que
    // gastar tiempo real de Timer.
    final setLogs = _MockCollection();
    final sessionDoc = _MockDoc();
    final sessions = _MockCollection();
    final userDoc = _MockDoc();
    final users = _MockCollection();
    final snap = _SnapshotDelReloj();

    when(() => firestore.collection('users')).thenReturn(users);
    when(() => users.doc(uid)).thenReturn(userDoc);
    when(() => userDoc.collection('sessions')).thenReturn(sessions);
    when(() => sessions.doc(sessionId)).thenReturn(sessionDoc);
    when(() => sessionDoc.collection('setLogs')).thenReturn(setLogs);
    when(() => setLogs.doc(watchDocId)).thenReturn(watchRef);
    when(() => watchRef.get()).thenAnswer(
      (_) => Future<DocumentSnapshot<Map<String, Object?>>>.delayed(
        const Duration(milliseconds: 5),
        () => snap,
      ),
    );
    // Sin esto, romper la adopción falla con un `MissingStub` críptico en vez
    // del `reason:` escrito abajo: un test que falla mal enseña mal.
    when(() => setLogs.doc()).thenReturn(nuevoRef);
    when(() => nuevoRef.id).thenReturn('id-autogenerado');
    when(() => nuevoRef.set(any())).thenAnswer((inv) async {
      escrituras.add(inv.positionalArguments[0] as Map<String, Object?>);
    });
    when(() => watchRef.set(any())).thenAnswer((inv) async {
      escrituras.add(inv.positionalArguments[0] as Map<String, Object?>);
    });

    final repo = SessionRepository(
      firestore: firestore,
      watchAdoptionReadTimeout: const Duration(milliseconds: 20),
    );

    final logged =
        await repo.addSetLog(uid: uid, sessionId: sessionId, setLog: serie());

    expect(
      logged.setLog.id,
      watchDocId,
      reason: 'con la lectura contestando a tiempo, la adopción tiene que '
          'ocurrir: es lo que evita el segundo documento de la misma serie.',
    );
  });

  test('la cota de producción sigue siendo holgada para una lectura normal',
      () {
    // Los dos tests de arriba INYECTAN 20 ms, así que el valor real de
    // `kWatchAdoptionReadTimeout` no lo mira nadie: un typo de `seconds: 2` a
    // `milliseconds: 2` entraría sin un solo rojo, y su consecuencia —saltear
    // la adopción y duplicar la serie— es invisible en el teléfono porque
    // `_dedupedLogs` la filtra del estado local. Quien la cuenta es el
    // servidor (`functions/src/ranking-aggregate.ts` relee `setLogs`).
    expect(
      kWatchAdoptionReadTimeout,
      greaterThanOrEqualTo(const Duration(seconds: 1)),
      reason: 'por debajo de un segundo la cota deja de proteger contra un '
          'stall y empieza a cortar lecturas sanas, que es el trade peligroso: '
          'un duplicado que el teléfono esconde y el ranking suma.',
    );
    expect(
      kWatchAdoptionReadTimeout,
      lessThan(kFirestoreReadTimeout),
      reason:
          'tiene que ser MÁS corta que la cota de las lecturas de arranque: '
          'ésta está en el camino de marcar una serie, no en el de abrir la '
          'pantalla.',
    );
  });
}

/// El snapshot del documento que dejó el reloj, con los campos que mira
/// `setLogDocHoldsSet`.
class _SnapshotDelReloj extends Mock
    implements DocumentSnapshot<Map<String, Object?>> {
  @override
  bool get exists => true;

  @override
  Map<String, Object?> data() => {
        'id': 'bench-press__1',
        'exerciseId': 'bench-press',
        'setNumber': 1,
      };
}
