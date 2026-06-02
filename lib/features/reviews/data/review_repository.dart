import 'package:cloud_firestore/cloud_firestore.dart'
    show CollectionReference, FirebaseFirestore;

import '../domain/review.dart';

/// Firestore repository for athlete → trainer reviews.
///
/// Reviews are stored at `reviews/{linkId}_{athleteId}` with upsert semantics.
/// REQ-RV-DATA-003..005. Fase 6 Etapa 7.
class ReviewRepository {
  ReviewRepository({required FirebaseFirestore firestore})
      : _firestore = firestore;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, Object?>> get _reviews =>
      _firestore.collection('reviews');

  /// Writes (or overwrites) the review at its deterministic id.
  ///
  /// Uses set without merge so that stale fields from a previous version are
  /// never retained. REQ-RV-DATA-003.
  Future<void> upsert(Review review) async {
    await _reviews.doc(review.id).set(review.toJson());
  }

  /// Returns the review for a given [linkId]/[athleteId] pair, or null if it
  /// does not exist. REQ-RV-DATA-004.
  Future<Review?> getForPair(String linkId, String athleteId) async {
    final id = Review.idFor(linkId, athleteId);
    final snap = await _reviews.doc(id).get();
    if (!snap.exists || snap.data() == null) return null;
    return Review.fromJson(snap.data()!);
  }

  /// Streams the review for a specific link (athlete+link pair), or null when
  /// absent. Used for edit-state detection in the write flow. Fase 6 Etapa 7.
  Stream<Review?> watchForLink(String linkId, String athleteId) {
    final id = Review.idFor(linkId, athleteId);
    return _reviews.doc(id).snapshots().map((snap) {
      if (!snap.exists || snap.data() == null) return null;
      return Review.fromJson(snap.data()!);
    });
  }

  /// Streams up to [limit] reviews for a trainer, sorted by createdAt DESC.
  ///
  /// Requires the composite index `(trainerId ASC, createdAt DESC)` deployed
  /// in `firestore.indexes.json`. REQ-RV-DATA-005, ADR-RV-013.
  Stream<List<Review>> watchForTrainer(
    String trainerId, {
    int limit = 10,
  }) {
    return _reviews
        .where('trainerId', isEqualTo: trainerId)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map((doc) => Review.fromJson(doc.data()))
              .toList(),
        );
  }
}
