import 'package:cloud_firestore/cloud_firestore.dart' show FirebaseFirestore;

/// Manages the `session_shares/{athleteId}` privacy-grant document.
///
/// The document body is `{ trainerId: <uid> }`. When present, the Firestore
/// security rule on `users/{uid}/sessions/{sessionId}` allows the named
/// trainer to read the athlete's sessions.
///
/// Only the athlete (auth.uid == athleteId) satisfies the write rule, so
/// this repository must only be called from the athlete's UI path.
class SessionShareRepository {
  SessionShareRepository({required FirebaseFirestore firestore})
      : _firestore = firestore;

  final FirebaseFirestore _firestore;

  /// Grant [trainerId] read access to [athleteId]'s sessions.
  Future<void> grant({
    required String athleteId,
    required String trainerId,
  }) {
    return _firestore
        .collection('session_shares')
        .doc(athleteId)
        .set({'trainerId': trainerId});
  }

  /// Revoke any existing grant for [athleteId].
  Future<void> revoke(String athleteId) {
    return _firestore.collection('session_shares').doc(athleteId).delete();
  }

  /// The trainer currently granted read access to [athleteId], or null when no
  /// grant exists.
  ///
  /// Read by the exercise-feedback composer: feedback the trainer cannot read
  /// has no recipient, so the composer asks for consent before writing instead
  /// of letting the athlete report pain into a void.
  Future<String?> grantedTrainerId(String athleteId) async {
    final snap =
        await _firestore.collection('session_shares').doc(athleteId).get();
    final data = snap.data();
    if (!snap.exists || data == null) return null;
    final trainerId = data['trainerId'];
    return trainerId is String && trainerId.isNotEmpty ? trainerId : null;
  }
}
