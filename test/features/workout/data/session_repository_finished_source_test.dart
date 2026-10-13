// session_repository_finished_source_test.dart — quién dice que la sesión
// desapareció importa tanto como el hecho.
//
// ─── El invariante ──────────────────────────────────────────────────────────
//
// `watchSessionFinished` traduce el documento de la sesión a un booleano que
// significa «alguien la cerró». Y un documento que NO EXISTE es una de las
// formas de decir eso… pero sólo si lo dice el servidor.
//
// Dicho por el caché no significa nada:
//
//   • la sesión puede estar todavía en la cola de escritura, sin ACKear —lo
//     normal si el atleta empezó a entrenar sin conexión—;
//   • o el servidor la rechazó (paywall, reglas) y el SDK revirtió la mutación
//     local, así que el documento se esfumó del caché.
//
// Tratar las dos cosas igual le mostraba al atleta «terminaste el entreno
// desde el reloj» sobre un rechazo. Una explicación falsa es peor que ninguna.
//
// ─── Por qué el invariante vive ACÁ y no en el notifier ─────────────────────
//
// La primera versión de esta defensa era un flag en `SessionNotifier` que
// recordaba si la creación había sido confirmada. No alcanzaba, y el agujero
// es instructivo: una sesión RETOMADA sale de `getActive`, que usa un `.get()`
// pelado y sin red devuelve el CACHÉ. El flag se prendía sobre algo que el
// servidor nunca había visto, y la mentira entraba por esa puerta.
//
// Firestore ya etiqueta cada snapshot con su procedencia. Un booleano que la
// recuerde es estado duplicado que puede divergir; leerla del snapshot no.
//
// ─── Por qué mocks y no `fake_cloud_firestore` ──────────────────────────────
//
// El fake deriva `isFromCache` de `options?.source == Source.cache`, así que
// para un `snapshots()` siempre es false: no puede representar el caso que
// este archivo prueba. Mismo trato —y mismo motivo— que
// `trainer_link_repository_cache_fria_test.dart`.
//
// `DocumentReference` y `DocumentSnapshot` están `@sealed` en
// `cloud_firestore`; mockearlas es la única forma de controlar `metadata`.
// ignore_for_file: subtype_of_sealed_class

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/features/workout/data/session_repository.dart';

class _MockFirestore extends Mock implements FirebaseFirestore {}

class _MockCollection extends Mock
    implements CollectionReference<Map<String, Object?>> {}

class _MockDoc extends Mock
    implements DocumentReference<Map<String, Object?>> {}

class _MockMetadata extends Mock implements SnapshotMetadata {}

class _Snapshot extends Mock implements DocumentSnapshot<Map<String, Object?>> {
  _Snapshot({
    required bool existe,
    required bool desdeElCache,
    bool escrituraPendiente = false,
    Map<String, Object?>? datos,
  })  : _existe = existe,
        _datos = datos,
        _metadata = (_MockMetadata()
          ..stub(desdeElCache: desdeElCache, pendiente: escrituraPendiente));

  final bool _existe;
  final Map<String, Object?>? _datos;
  final _MockMetadata _metadata;

  /// Mismos DATOS que [otro]: lo único que puede cambiar es la metadata.
  bool mismosDatosQue(_Snapshot otro) =>
      _existe == otro._existe && mapEquals(_datos, otro._datos);

  @override
  bool get exists => _existe;

  @override
  SnapshotMetadata get metadata => _metadata;

  @override
  Map<String, Object?>? data() => _datos;
}

extension on _MockMetadata {
  void stub({required bool desdeElCache, required bool pendiente}) {
    when(() => isFromCache).thenReturn(desdeElCache);
    when(() => hasPendingWrites).thenReturn(pendiente);
  }
}

/// Lo que el SDK le entrega a un listener, a partir de lo que pasa en el doc.
///
/// Sin `includeMetadataChanges: true`, un snapshot cuyos DATOS son iguales a
/// los del anterior —sólo cambió `isFromCache` o `hasPendingWrites`— **no se
/// emite**. Es el `shouldRaiseEvent` del core de Firestore, el mismo
/// comportamiento que documenta `follow_repository.dart`. El ACK del servidor
/// a una escritura propia es exactamente eso: mismos datos,
/// `hasPendingWrites` true → false.
///
/// Un mock que emite todo sin mirar el flag no puede ver ese bug: el código
/// que se olvida del flag pasaría igual.
List<_Snapshot> _loQueEmiteElSdk(
  List<_Snapshot> enElDoc, {
  required bool includeMetadataChanges,
}) {
  if (includeMetadataChanges) return enElDoc;
  final out = <_Snapshot>[];
  for (final s in enElDoc) {
    if (out.isNotEmpty && s.mismosDatosQue(out.last)) continue;
    out.add(s);
  }
  return out;
}

void main() {
  const uid = 'u1';
  const sessionId = 's1';

  setUpAll(() => registerFallbackValue(ListenSource.defaultSource));

  /// Arma el repositorio sobre un documento por el que pasan [snaps] en orden.
  /// Lo que llega al listener depende de `includeMetadataChanges`, como en el
  /// SDK real — ver [_loQueEmiteElSdk].
  SessionRepository repoQueEmite(List<_Snapshot> snaps) {
    final firestore = _MockFirestore();
    final users = _MockCollection();
    final userDoc = _MockDoc();
    final sessions = _MockCollection();
    final sessionDoc = _MockDoc();

    when(() => firestore.collection('users')).thenReturn(users);
    when(() => users.doc(uid)).thenReturn(userDoc);
    when(() => userDoc.collection('sessions')).thenReturn(sessions);
    when(() => sessions.doc(sessionId)).thenReturn(sessionDoc);
    when(
      () => sessionDoc.snapshots(
        includeMetadataChanges: any(named: 'includeMetadataChanges'),
        source: any(named: 'source'),
      ),
    ).thenAnswer((inv) {
      final conMetadata =
          inv.namedArguments[#includeMetadataChanges] as bool? ?? false;
      return Stream<DocumentSnapshot<Map<String, Object?>>>.fromIterable(
        _loQueEmiteElSdk(snaps, includeMetadataChanges: conMetadata),
      );
    });
    return SessionRepository(firestore: firestore);
  }

  test('un «no existe» del SERVIDOR sí significa que la sesión se cerró',
      () async {
    final repo = repoQueEmite([
      // Primero existió DE VERDAD: confirmada por el servidor, sin escrituras
      // locales pendientes. Es la sesión que el reloj después cierra.
      _Snapshot(
        existe: true,
        desdeElCache: false,
        datos: const {'finishedAt': null},
      ),
      _Snapshot(existe: false, desdeElCache: false),
    ]);

    await expectLater(
      repo.watchSessionFinished(uid: uid, sessionId: sessionId),
      emitsInOrder([false, true]),
      reason: 'es el camino por el que el reloj cierra un entreno y el '
          'teléfono se entera. Romperlo dejaría al atleta entrenando sobre una '
          'sesión que ya no existe.',
    );
  });

  test('un «no existe» del CACHÉ no significa nada', () async {
    final repo = repoQueEmite([_Snapshot(existe: false, desdeElCache: true)]);

    await expectLater(
      repo.watchSessionFinished(uid: uid, sessionId: sessionId),
      emits(false),
      reason: 'el documento puede estar sin ACKear —entreno empezado sin red— '
          'o el servidor pudo haberlo rechazado y el SDK revirtió la mutación. '
          'Decirle al atleta que cerró el entreno desde el reloj sobre un '
          'rechazo de paywall es una explicación falsa.',
    );
  });

  test(
      'un create RECHAZADO no se lee como «terminada», aunque la ausencia '
      'venga del servidor', () async {
    // ⚠️ ESTE es el caso original del PR, y casi se queda sin cobertura.
    //
    // La aserción end-to-end que lo cubría vivía en el test del notifier y se
    // borró al mudar el invariante acá. Sin este test, el bug que el PR vino a
    // matar quedaba sin un solo guard.
    //
    // El agujero de la versión anterior: mirar sólo `isFromCache` separa «no
    // sé» de «habló el servidor», pero NO separa las dos cosas que el servidor
    // puede estar diciendo — «existió y ya no está» (terminada) de «nunca
    // existió» (rechazada). Con red, un create denegado por las reglas produce
    // una ausencia que TAMBIÉN viene del servidor: el SDK revierte la mutación
    // local y empuja el snapshot.
    //
    // Lo que las distingue es si el documento llegó a existir SIN una
    // escritura local pendiente inventándolo.
    final repo = repoQueEmite([
      // Lo que ve el atleta al tocar Empezar: el doc "existe", pero sólo
      // porque hay una escritura local sin confirmar.
      _Snapshot(
        existe: true,
        desdeElCache: false,
        escrituraPendiente: true,
        datos: const {'finishedAt': null},
      ),
      // Las reglas lo deniegan, el SDK revierte, y el servidor empuja la
      // ausencia.
      _Snapshot(existe: false, desdeElCache: false),
    ]);

    await expectLater(
      repo.watchSessionFinished(uid: uid, sessionId: sessionId),
      // `emitsDone` y no un segundo `false`: el stream sólo emite cambios de
      // valor (`distinct`), así que lo que importa es que NUNCA llegue `true`.
      emitsInOrder([false, emitsDone]),
      reason: 'la sesión nunca existió en el servidor, así que su ausencia no '
          'significa que alguien la haya terminado. Leerlo como «terminada» le '
          'dice al atleta que cerró el entreno desde la muñeca sobre un '
          'rechazo de paywall.',
    );
  });

  test(
      'una sesión creada en ESTE dispositivo sí se lee como terminada cuando '
      'desaparece', () async {
    // El ACK del servidor al create propio no cambia ningún dato: sólo
    // `hasPendingWrites` pasa de true a false. Sin `includeMetadataChanges`
    // el SDK no emite ese snapshot, `existioDeVerdad` no se prendía nunca, y
    // la desaparición posterior —confirmada por el servidor— se leía como
    // «nunca existió». El player quedaba vivo sobre una sesión borrada.
    const datos = {'finishedAt': null};
    final repo = repoQueEmite([
      // Tocó Empezar: escritura local sin confirmar.
      _Snapshot(
        existe: true,
        desdeElCache: false,
        escrituraPendiente: true,
        datos: datos,
      ),
      // El servidor la ACKea. Mismos datos: cambio SÓLO de metadata.
      _Snapshot(existe: true, desdeElCache: false, datos: datos),
      // Después alguien la borra, y lo dice el servidor.
      _Snapshot(existe: false, desdeElCache: false),
    ]);

    await expectLater(
      repo.watchSessionFinished(uid: uid, sessionId: sessionId),
      emitsInOrder([false, true]),
      reason: 'la sesión existió en el servidor —el ACK lo prueba— así que '
          'su desaparición es un cierre. Si el ACK no se escucha, el teléfono '
          'nunca se entera y sigue escribiendo sobre una sesión que no existe.',
    );
  });

  test('los snapshots de sólo-metadata no re-emiten el mismo valor', () async {
    // Escuchar la metadata es lo que arregla el caso de arriba, pero tiene un
    // costo: cada ACK y cada cambio de `isFromCache` es una emisión más. Los
    // consumidores (notifier del player, sesión del reloj) reaccionan a cada
    // valor; que vean sólo los CAMBIOS es parte del contrato.
    const datos = {'finishedAt': null};
    final repo = repoQueEmite([
      _Snapshot(existe: true, desdeElCache: true, datos: datos),
      _Snapshot(
        existe: true,
        desdeElCache: false,
        escrituraPendiente: true,
        datos: datos,
      ),
      _Snapshot(existe: true, desdeElCache: false, datos: datos),
    ]);

    expect(
      await repo.watchSessionFinished(uid: uid, sessionId: sessionId).toList(),
      [false],
    );
  });
}
