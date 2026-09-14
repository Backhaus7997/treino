import 'package:cloud_firestore/cloud_firestore.dart'
    show CollectionReference, DocumentSnapshot, FirebaseFirestore;

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
  Stream<List<String>> watchBlockedUids(String blockerUid) =>
      _blocks.where('blockerUid', isEqualTo: blockerUid).snapshots().map(
          (s) => s.docs.map((d) => d.data()['blockedUid']! as String).toList());

  Block? _fromDoc(DocumentSnapshot<Map<String, Object?>> snap) {
    final data = snap.data();
    if (!snap.exists || data == null) return null;
    return Block.fromJson({...data, 'id': snap.id});
  }
}
