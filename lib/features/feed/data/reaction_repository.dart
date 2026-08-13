import 'package:cloud_firestore/cloud_firestore.dart'
    show CollectionReference, DocumentSnapshot, FieldValue, FirebaseFirestore;

import '../domain/reaction.dart';
import '../domain/reaction_type.dart';

class ReactionRepository {
  ReactionRepository({required FirebaseFirestore firestore})
      : _firestore = firestore;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, Object?>> get _posts =>
      _firestore.collection('posts');

  CollectionReference<Map<String, Object?>> _reactions(String postId) =>
      _posts.doc(postId).collection('reactions');

  Future<void> react({
    required String postId,
    required String uid,
    required ReactionType type,
  }) async {
    await _reactions(postId).doc(uid).set({
      'type': type.toJson(),
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> removeReaction({
    required String postId,
    required String uid,
  }) async {
    await _reactions(postId).doc(uid).delete();
  }

  Stream<Reaction?> watchMyReaction({
    required String postId,
    required String uid,
  }) {
    return _reactions(postId).doc(uid).snapshots().map(_fromDoc);
  }

  Reaction? _fromDoc(DocumentSnapshot<Map<String, Object?>> snap) {
    final data = snap.data();
    if (!snap.exists || data == null) return null;
    return Reaction.fromJson({...data, 'uid': snap.id});
  }
}
