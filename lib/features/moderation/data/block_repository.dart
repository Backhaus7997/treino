import 'package:cloud_firestore/cloud_firestore.dart'
    show
        CollectionReference,
        DocumentSnapshot,
        FirebaseException,
        FirebaseFirestore,
        QuerySnapshot;

import '../domain/block.dart';

/// Acceso a `blocks/{blockerUid}_{blockedUid}`.
///
/// Copia el molde de `FollowRepository` (arista dirigida, id sin ordenar,
/// `members` para `array-contains`), simplificado: bloquear no tiene
/// `pending → accepted`, así que no hay un método de aceptar ni un `status`.
///
/// [watchBlockedUids] filtra por `blockerUid`, no por `members` — a
/// propósito. El diseño (`design.md` → "El oráculo de existencia") sólo deja
/// leer el documento al bloqueador; una query por `members` intentaría
/// devolver también las aristas donde ESTE uid es el BLOQUEADO, que las
/// reglas van a rechazar.
class BlockRepository {
  BlockRepository({required FirebaseFirestore firestore})
      : _firestore = firestore;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, Object?>> get _blocks =>
      _firestore.collection('blocks');

  /// Crea la arista `blockerUid → blockedUid`.
  ///
  /// Idempotente: si ya existe la devuelve sin volver a escribir, mismo
  /// criterio que `FollowRepository.follow`.
  Future<Block> block(String blockerUid, String blockedUid) async {
    final id = Block.edgeId(blockerUid, blockedUid);
    final ref = _blocks.doc(id);

    final snap = await ref.get();
    if (snap.exists) return _fromDoc(snap)!;

    final edge = Block(
      id: id,
      blockerUid: blockerUid,
      blockedUid: blockedUid,
      members: [blockerUid, blockedUid],
      createdAt: DateTime.now().toUtc(),
    );
    await ref.set(edge.toJson());
    return edge;
  }

  /// Borra la arista `blockerUid → blockedUid`. No-op si no existía.
  Future<void> unblock(String blockerUid, String blockedUid) =>
      _blocks.doc(Block.edgeId(blockerUid, blockedUid)).delete();

  /// UIDs que [blockerUid] bloqueó, en vivo.
  Stream<List<String>> watchBlockedUids(String blockerUid) => _blocks
      .where('blockerUid', isEqualTo: blockerUid)
      .snapshots()
      .map(_blockedUidsOf);

  /// Como [watchBlockedUids], pero para quien MUESTRA la lista: la primera
  /// respuesta tiene que estar confirmada, o tira `unavailable`.
  ///
  /// Sin red y con la caché fría, una query no falla: contesta con un
  /// `QuerySnapshot` VACÍO con `isFromCache == true`. [watchBlockedUids] lo
  /// publica como `[]`, y para el feed, el chat y `myBlockedUidsProvider` eso es
  /// lo correcto —ante la duda asumen «sin bloqueos», y ni siquiera pueden
  /// tirar: el feed espera `blockedUidsProvider.future` y, con la guarda ahí, un
  /// usuario sin bloqueos perdería los posts cacheados sin red—. Pero una
  /// pantalla que dice «No bloqueaste a nadie» está afirmando algo sobre el
  /// usuario que no pudo verificar (AGENTS.md §11.1).
  ///
  /// Misma regla que `PostRepository._exigirRespuestaConfirmada` (#1744): vacío
  /// DESDE LA CACHÉ es «no pude preguntar»; con bloqueados cacheados se muestran
  /// (datos viejos pero reales), y un vacío confirmado por el servidor es un
  /// vacío real. Va sobre un `get()` y no sobre `snapshots()` porque el `get()`
  /// espera al servidor cuando hay red y sólo cae a la caché cuando no la hay;
  /// el listener entrega la caché vacía antes que el servidor aun online, y
  /// distinguirlas ahí pediría `includeMetadataChanges` y un timeout.
  ///
  /// La guarda corre UNA vez, sobre la carga inicial. Las snapshots siguientes
  /// —el listener, para que Desbloquear saque la fila— no se guardan: que la
  /// última fila se borre sin red deja una snapshot vacía de la caché que SÍ es
  /// un hecho (lo acaba de hacer el usuario).
  Stream<List<String>> watchBlockedUidsConfirmed(String blockerUid) async* {
    final query = _blocks.where('blockerUid', isEqualTo: blockerUid);
    final inicial = await query.get();
    _exigirRespuestaConfirmada(inicial);
    yield _blockedUidsOf(inicial);
    yield* query.snapshots().map(_blockedUidsOf);
  }

  static void _exigirRespuestaConfirmada(
    QuerySnapshot<Map<String, Object?>> snap,
  ) {
    if (snap.docs.isNotEmpty || !snap.metadata.isFromCache) return;
    throw FirebaseException(
      plugin: 'cloud_firestore',
      code: 'unavailable',
      message: 'No se pudo confirmar la lista de bloqueados con el servidor '
          '(sin conexión).',
    );
  }

  static List<String> _blockedUidsOf(QuerySnapshot<Map<String, Object?>> s) =>
      s.docs.map((d) => d.data()['blockedUid']! as String).toList();

  Block? _fromDoc(DocumentSnapshot<Map<String, Object?>> snap) {
    final data = snap.data();
    if (!snap.exists || data == null) return null;
    return Block.fromJson({...data, 'id': snap.id});
  }
}
