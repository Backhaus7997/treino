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
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/features/workout/data/session_repository.dart';

class _MockFirestore extends Mock implements FirebaseFirestore {}

class _MockCollection extends Mock
    implements CollectionReference<Map<String, Object?>> {}

class _MockDoc extends Mock
    implements DocumentReference<Map<String, Object?>> {}

class _MockMetadata extends Mock implements SnapshotMetadata {}

class _SnapshotAusente extends Mock
    implements DocumentSnapshot<Map<String, Object?>> {
  _SnapshotAusente({required bool desdeElCache})
      : _metadata = (_MockMetadata()..stubIsFromCache(desdeElCache));

  final _MockMetadata _metadata;

  @override
  bool get exists => false;

  @override
  SnapshotMetadata get metadata => _metadata;

  @override
  Map<String, Object?>? data() => null;
}

extension on _MockMetadata {
  void stubIsFromCache(bool v) => when(() => isFromCache).thenReturn(v);
}

void main() {
  const uid = 'u1';
  const sessionId = 's1';

  /// Arma el repositorio sobre un `snapshots()` que emite [snap].
  SessionRepository repoQueEmite(DocumentSnapshot<Map<String, Object?>> snap) {
    final firestore = _MockFirestore();
    final users = _MockCollection();
    final userDoc = _MockDoc();
    final sessions = _MockCollection();
    final sessionDoc = _MockDoc();

    when(() => firestore.collection('users')).thenReturn(users);
    when(() => users.doc(uid)).thenReturn(userDoc);
    when(() => userDoc.collection('sessions')).thenReturn(sessions);
    when(() => sessions.doc(sessionId)).thenReturn(sessionDoc);
    when(sessionDoc.snapshots).thenAnswer(
      (_) => Stream<DocumentSnapshot<Map<String, Object?>>>.value(snap),
    );
    return SessionRepository(firestore: firestore);
  }

  test('un «no existe» del SERVIDOR sí significa que la sesión se cerró',
      () async {
    final repo = repoQueEmite(_SnapshotAusente(desdeElCache: false));

    await expectLater(
      repo.watchSessionFinished(uid: uid, sessionId: sessionId),
      emits(true),
      reason: 'es el camino por el que el reloj cierra un entreno y el '
          'teléfono se entera. Romperlo dejaría al atleta entrenando sobre una '
          'sesión que ya no existe.',
    );
  });

  test('un «no existe» del CACHÉ no significa nada', () async {
    final repo = repoQueEmite(_SnapshotAusente(desdeElCache: true));

    await expectLater(
      repo.watchSessionFinished(uid: uid, sessionId: sessionId),
      emits(false),
      reason: 'el documento puede estar sin ACKear —entreno empezado sin red— '
          'o el servidor pudo haberlo rechazado y el SDK revirtió la mutación. '
          'Decirle al atleta que cerró el entreno desde el reloj sobre un '
          'rechazo de paywall es una explicación falsa.',
    );
  });
}
