import 'dart:developer' as developer;

import 'package:cloud_firestore/cloud_firestore.dart'
    show CollectionReference, DocumentSnapshot, FirebaseFirestore;

import '../domain/exercise_feedback.dart';

/// Reads and writes athlete-authored per-exercise feedback.
///
/// Lives in its own repository rather than inside [SessionRepository] because
/// the write path is independent of the session lifecycle (a feedback entry can
/// be created at any point during an active session and never participates in
/// the volume/streak recompute that `finish` performs).
///
/// Path: `users/{uid}/sessions/{sessionId}/exerciseFeedback/{id}` — a sibling of
/// `setLogs`, which is what makes the existing `session_shares` read grant
/// apply unchanged (owner OR linked trainer reads, owner-only writes).
class ExerciseFeedbackRepository {
  ExerciseFeedbackRepository({required FirebaseFirestore firestore})
      : _firestore = firestore;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, Object?>> _feedback(
    String uid,
    String sessionId,
  ) =>
      _firestore
          .collection('users')
          .doc(uid)
          .collection('sessions')
          .doc(sessionId)
          .collection('exerciseFeedback');

  // ─── id allocation ──────────────────────────────────────────────────────

  /// Allocates a doc id without writing anything.
  ///
  /// Callers that attach a photo need the id first, so the Storage object can be
  /// named after the document it belongs to before a single byte is uploaded —
  /// the same ordering `PostPhotoUploadService` relies on.
  String newFeedbackId({required String uid, required String sessionId}) =>
      _feedback(uid, sessionId).doc().id;

  // ─── create ─────────────────────────────────────────────────────────────

  /// Persists one feedback entry and returns it with the generated doc id.
  ///
  /// Throws [ArgumentError] when the entry carries neither text nor a photo —
  /// the rules reject it too, but failing here keeps the round-trip out of the
  /// picture and gives the composer a precise error.
  Future<ExerciseFeedback> create({
    required String uid,
    required String sessionId,
    required ExerciseFeedback feedback,
  }) async {
    if (!feedback.hasContent) {
      throw ArgumentError.value(
        feedback,
        'feedback',
        'ExerciseFeedback requires text or a photo',
      );
    }
    final ref = _feedback(uid, sessionId).doc();
    final withId = feedback.copyWith(id: ref.id);
    await ref.set(withId.toJson());
    return withId;
  }

  /// Writes an entry whose id was allocated earlier via [newFeedbackId].
  ///
  /// Used by the photo path: the id has to exist before the upload, so the
  /// caller owns it and this method must not mint a new one.
  Future<void> createWithId({
    required String uid,
    required String sessionId,
    required ExerciseFeedback feedback,
  }) async {
    if (feedback.id.isEmpty) {
      throw ArgumentError.value(
        feedback.id,
        'feedback.id',
        'createWithId requires an id — use create() to have one generated',
      );
    }
    if (!feedback.hasContent) {
      throw ArgumentError.value(
        feedback,
        'feedback',
        'ExerciseFeedback requires text or a photo',
      );
    }
    await _feedback(uid, sessionId).doc(feedback.id).set(feedback.toJson());
  }

  // ─── delete ─────────────────────────────────────────────────────────────

  /// Hard-deletes a feedback doc.
  ///
  /// Delete-and-recreate is the only way to amend an entry: the rules deny
  /// `update` so [ExerciseFeedback.photoUrl] can never drift from
  /// [ExerciseFeedback.photoPath] (same reasoning as `athlete_files`).
  ///
  /// The Storage object, when present, is removed by the caller — this
  /// repository owns Firestore only.
  Future<void> delete({
    required String uid,
    required String sessionId,
    required String feedbackId,
  }) async {
    await _feedback(uid, sessionId).doc(feedbackId).delete();
  }

  // ─── list ───────────────────────────────────────────────────────────────

  /// All feedback for a session, oldest first.
  ///
  /// Ordered by `createdAt` so the trainer reads the session in the sequence
  /// the athlete lived it. A malformed doc is skipped rather than thrown:
  /// the trainer-side surfaces read other users' documents, and one bad entry
  /// must not blank out the whole session view (same defence as
  /// `SessionRepository._sessionFromDoc`).
  Future<List<ExerciseFeedback>> list({
    required String uid,
    required String sessionId,
  }) async {
    final snap = await _feedback(uid, sessionId).orderBy('createdAt').get();
    return snap.docs.map(_fromDoc).whereType<ExerciseFeedback>().toList();
  }

  /// Live feedback for a session, oldest first. Used by the player so an entry
  /// the athlete just wrote appears without a manual refresh.
  Stream<List<ExerciseFeedback>> watch({
    required String uid,
    required String sessionId,
  }) {
    return _feedback(uid, sessionId).orderBy('createdAt').snapshots().map(
          (snap) =>
              snap.docs.map(_fromDoc).whereType<ExerciseFeedback>().toList(),
        );
  }

  // ─── Private helpers ────────────────────────────────────────────────────

  ExerciseFeedback? _fromDoc(DocumentSnapshot<Map<String, Object?>> snap) {
    final data = snap.data();
    if (!snap.exists || data == null) return null;
    try {
      return ExerciseFeedback.fromJson({...data, 'id': snap.id});
    } catch (e, st) {
      developer.log(
        'Malformed exerciseFeedback doc ${snap.id} skipped',
        name: 'ExerciseFeedbackRepository',
        error: e,
        stackTrace: st,
      );
      return null;
    }
  }
}
