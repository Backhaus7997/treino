import 'dart:developer' as developer;

import 'package:cloud_firestore/cloud_firestore.dart'
    show CollectionReference, DocumentSnapshot, FirebaseFirestore, Timestamp;

import '../../profile/domain/experience_level.dart';
import '../../profile/domain/gender.dart';
import '../domain/profile_share.dart';

/// Manages the `profile_shares/{athleteId}` consent document.
///
/// The document body stores the trainer id plus the athlete's shared personal
/// fields (`trainerId`, `phone`, `bornAt`, `heightCm`, `bodyWeightKg`,
/// `gender`, `experienceLevel`, `updatedAt`).
///
/// Security rules mirror `session_shares`:
///   - read:  auth.uid == athleteId OR auth.uid == resource.data.trainerId
///   - write: auth.uid == athleteId (athlete-only)
///
/// Slice 1 shipped `watchForAthlete` (web read). Slice 2 adds `grant` / `revoke`
/// for the athlete's mobile consent toggle.
class ProfileShareRepository {
  ProfileShareRepository({required FirebaseFirestore firestore})
      : _firestore = firestore;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, Object?>> get _collection =>
      _firestore.collection('profile_shares');

  /// Watch `profile_shares/{athleteId}`.
  ///
  /// Emits `null` when the doc does not exist (athlete has not opted in yet).
  /// Errors are propagated to the stream consumer (e.g. `permission-denied`
  /// when no valid grant exists — callers should handle gracefully).
  Stream<ProfileShare?> watchForAthlete(String athleteId) {
    return _collection.doc(athleteId).snapshots().map(_fromDoc);
  }

  // ─── grant ────────────────────────────────────────────────────────────────
  //
  // Writes (or replaces) the `profile_shares/{athleteId}` consent doc.
  // Called from the athlete's mobile consent toggle when they opt IN.
  //
  // Only non-null fields are included in the Firestore document so the coach
  // does not see "null" for fields the athlete hasn't filled in their profile.
  // `updatedAt` is always written (the coach uses it to detect stale data).

  /// Grant [trainerId] access to [athleteId]'s personal data.
  ///
  /// Writes a snapshot of the athlete's profile fields as of call time.
  /// If a previous grant exists it is REPLACED (re-toggle = refresh snapshot).
  Future<void> grant({
    required String athleteId,
    required String trainerId,
    String? phone,
    DateTime? bornAt,
    int? heightCm,
    double? bodyWeightKg,
    Gender? gender,
    ExperienceLevel? experienceLevel,
    required DateTime updatedAt,
  }) {
    final doc = <String, Object?>{
      'trainerId': trainerId,
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
    if (phone != null) doc['phone'] = phone;
    if (bornAt != null) doc['bornAt'] = Timestamp.fromDate(bornAt);
    if (heightCm != null) doc['heightCm'] = heightCm;
    if (bodyWeightKg != null) doc['bodyWeightKg'] = bodyWeightKg;
    if (gender != null) doc['gender'] = gender.toJson();
    if (experienceLevel != null) {
      doc['experienceLevel'] = experienceLevel.toJson();
    }
    return _collection.doc(athleteId).set(doc);
  }

  // ─── revoke ───────────────────────────────────────────────────────────────
  //
  // Deletes the consent doc. Called when the athlete opts OUT.
  // Mirrors SessionShareRepository.revoke — deletion is idempotent on
  // FakeFirebaseFirestore (no-op if doc doesn't exist).

  /// Revoke any existing profile share for [athleteId].
  ///
  /// Deletes the `profile_shares/{athleteId}` document. Idempotent — calling
  /// when no grant exists is a no-op.
  Future<void> revoke(String athleteId) {
    return _collection.doc(athleteId).delete();
  }

  ProfileShare? _fromDoc(DocumentSnapshot<Map<String, Object?>> snap) {
    final data = snap.data();
    if (!snap.exists || data == null) return null;
    try {
      return ProfileShare.fromJson(data);
    } catch (e, st) {
      developer.log(
        'ProfileShareRepository: skipped unparseable doc ${snap.id}',
        error: e,
        stackTrace: st,
      );
      return null;
    }
  }
}
