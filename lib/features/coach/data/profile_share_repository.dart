import 'dart:developer' as developer;

import 'package:cloud_firestore/cloud_firestore.dart'
    show CollectionReference, DocumentSnapshot, FirebaseFirestore;

import '../domain/profile_share.dart';

/// Manages the `profile_shares/{athleteId}` consent document.
///
/// The document body stores the trainer id plus the athlete's shared personal
/// fields (`trainerId`, `phone`, `bornAt`, `heightCm`, `bodyWeightKg`,
/// `gender`, `experienceLevel`, `updatedAt`).
///
/// Security rules mirror `session_shares`:
///   - read:  auth.uid == athleteId OR auth.uid == resource.data.trainerId
///   - write: auth.uid == athleteId (athlete-only — mobile slice)
///
/// This repository is **web read-only** for Slice 1. Grant/revoke are
/// intentionally absent here; they are implemented in the mobile consent UI
/// (Slice 2).
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
