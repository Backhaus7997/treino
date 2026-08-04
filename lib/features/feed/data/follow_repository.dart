import 'package:cloud_firestore/cloud_firestore.dart'
    show CollectionReference, DocumentSnapshot, FirebaseFirestore, Query;

import '../domain/follow.dart';
import '../domain/follow_status.dart';

/// Acceso a `follows/{followerUid}_{followeeUid}` — el grafo social dirigido.
///
/// Reemplaza a `FriendshipRepository`, que trataba la relación como UN
/// documento por par: ahí `delete()` era el mismo método para cancelar una
/// solicitud, rechazarla y dejar de seguir, y borraba la relación entera para
/// los dos. Acá cada dirección es un documento propio, así que esas tres cosas
/// son la misma operación pero sobre la arista que corresponde, y nunca tocan
/// la inversa.
///
/// **No existe `followersOf`**: no tiene consumidor en este change
/// (ADR-FOLLOW-009). La pantalla de seguidores/seguidos vive en `follow-lists`,
/// y agregar el método ahora sería código muerto con un índice que lo sostenga.
class FollowRepository {
  FollowRepository({required FirebaseFirestore firestore})
      : _firestore = firestore;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, Object?>> get _follows =>
      _firestore.collection('follows');

  /// Crea la arista `myUid → targetUid`.
  ///
  /// Cuando [targetIsPublic] es `true` (cuenta pública, el default del
  /// producto) la arista nace `accepted` y no hay solicitud que aprobar. Si la
  /// cuenta es privada nace `pending` y solo el destinatario puede promoverla
  /// con [acceptRequest]. Las rules hacen cumplir las dos cosas del lado del
  /// servidor con un `get()` sobre `userPublicProfiles`; acá se replica para no
  /// mandar un write que va a rebotar.
  ///
  /// Idempotente: si la arista ya existe la devuelve sin escribir. Importa
  /// porque, si no, volver a tocar SEGUIR sobre una cuenta que pasó de pública
  /// a privada degradaría un `accepted` a `pending`.
  Future<Follow> follow(
    String myUid,
    String targetUid, {
    required bool targetIsPublic,
  }) async {
    final id = Follow.edgeId(myUid, targetUid);
    final ref = _follows.doc(id);

    final snap = await ref.get();
    if (snap.exists) return _fromDoc(snap)!;

    final edge = Follow(
      id: id,
      followerUid: myUid,
      followeeUid: targetUid,
      status: targetIsPublic ? FollowStatus.accepted : FollowStatus.pending,
      members: [myUid, targetUid],
      createdAt: DateTime.now().toUtc(),
    );
    await ref.set(edge.toJson());
    return edge;
  }

  /// Promueve una arista `pending` a `accepted`.
  ///
  /// Solo el `followeeUid` puede hacerlo: aceptar es el acto de la persona a la
  /// que quieren seguir. Tira [StateError] si [myUid] no es ese, en vez de
  /// mandar un write que las rules van a rechazar igual.
  Future<void> acceptRequest(String edgeId, String myUid) async {
    final ref = _follows.doc(edgeId);
    final snap = await ref.get();
    final edge = _fromDoc(snap);
    if (edge == null) {
      throw StateError('No existe la arista $edgeId');
    }
    if (edge.followeeUid != myUid) {
      throw StateError(
        'Solo el destinatario de la solicitud puede aceptarla '
        '($myUid no es el followee de $edgeId)',
      );
    }
    await ref.update({'status': FollowStatus.accepted.toJson()});
  }

  /// Borra UNA arista.
  ///
  /// Es la misma operación para dejar de seguir, cancelar una solicitud enviada
  /// y rechazar una recibida — cambia quién la invoca, no qué hace. **Nunca
  /// toca la dirección inversa**: en un par que se sigue mutuamente, dejar de
  /// seguir corta un solo sentido.
  Future<void> deleteEdge(String edgeId) => _follows.doc(edgeId).delete();

  /// UIDs a los que [uid] sigue con la relación ya aceptada.
  Future<List<String>> followingOf(String uid) async {
    final snap = await _followingQuery(uid).get();
    return snap.docs.map((d) => d.data()['followeeUid']! as String).toList();
  }

  Stream<List<String>> watchFollowingOf(String uid) =>
      _followingQuery(uid).snapshots().map(
            (s) =>
                s.docs.map((d) => d.data()['followeeUid']! as String).toList(),
          );

  /// Solicitudes que [uid] RECIBIÓ y todavía no resolvió.
  ///
  /// El filtro por `followeeUid` es server-side a propósito: filtrar en memoria
  /// obligaría a traerse también las solicitudes enviadas, que con las rules
  /// nuevas el usuario ni siquiera podría leer en bloque.
  Future<List<Follow>> pendingReceivedFor(String uid) async {
    final snap = await _pendingReceivedQuery(uid).get();
    return snap.docs.map(_fromDoc).whereType<Follow>().toList();
  }

  Stream<List<Follow>> watchPendingReceivedFor(String uid) =>
      _pendingReceivedQuery(uid).snapshots().map(
            (s) => s.docs.map(_fromDoc).whereType<Follow>().toList(),
          );

  /// Una arista puntual por doc id. Devuelve `null` si no existe.
  ///
  /// Las dos direcciones de un par se consultan por separado; combinarlas es lo
  /// que da los cuatro estados posibles entre dos usuarios.
  Future<Follow?> getEdge(String edgeId) async =>
      _fromDoc(await _follows.doc(edgeId).get());

  Stream<Follow?> watchEdge(String edgeId) =>
      _follows.doc(edgeId).snapshots().map(_fromDoc);

  /// TODAS las aristas que tocan a [uid], en cualquier dirección y estado.
  ///
  /// Resuelto con un `array-contains` sobre `members` para no pagar dos
  /// queries. Es el insumo del cascade de borrado de cuenta y de la exclusión
  /// de candidatos en las sugerencias.
  Future<List<Follow>> allOf(String uid) async {
    final snap = await _follows.where('members', arrayContains: uid).get();
    return snap.docs.map(_fromDoc).whereType<Follow>().toList();
  }

  Query<Map<String, Object?>> _followingQuery(String uid) => _follows
      .where('followerUid', isEqualTo: uid)
      .where('status', isEqualTo: FollowStatus.accepted.toJson());

  Query<Map<String, Object?>> _pendingReceivedQuery(String uid) => _follows
      .where('followeeUid', isEqualTo: uid)
      .where('status', isEqualTo: FollowStatus.pending.toJson());

  Follow? _fromDoc(DocumentSnapshot<Map<String, Object?>> snap) {
    final data = snap.data();
    if (!snap.exists || data == null) return null;
    // Se inyecta `snap.id` para que un doc creado a mano (consola de Firestore,
    // script de migración) deserialice aunque omita `id` en el body.
    return Follow.fromJson({...data, 'id': snap.id});
  }
}
