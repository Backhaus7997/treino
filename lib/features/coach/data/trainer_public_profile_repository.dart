import 'package:cloud_firestore/cloud_firestore.dart'
    show CollectionReference, FirebaseFirestore;

import '../domain/trainer_public_profile.dart';
import '../domain/trainer_specialty.dart';

/// Repository for the `trainerPublicProfiles` collection.
///
/// Readable by any authenticated user; writable only by the owner via
/// [UserRepository] dual-write.
///
/// Query strategy per design D9/D10:
///   - [listByGeohashPrefix]: Firestore range query on `trainerGeohash`.
///     Optional [specialty] filter applied client-side (D10 — no compound index).
///   - [listAll]: Firestore `orderBy displayNameLowercase ASC` with limit 50 (D14).
///     Optional [specialty] filter applied client-side.
///   - [getById]: single doc read, returns null if `!exists` (D12).
///
/// REQ-COACH-DISC-DATA-004..007.
class TrainerPublicProfileRepository {
  TrainerPublicProfileRepository({required FirebaseFirestore firestore})
      : _firestore = firestore;

  final FirebaseFirestore _firestore;

  /// Upper bound sentinel for geohash prefix range queries.
  static const _upperBoundSuffix = '￿';

  CollectionReference<Map<String, Object?>> get _col =>
      _firestore.collection('trainerPublicProfiles');

  /// Returns trainers whose `trainerGeohash` starts with [prefix5].
  ///
  /// Uses Firestore range query:
  ///   `>= prefix` AND `< prefix + '￿'`
  ///
  /// If [specialty] is provided, the result is filtered client-side
  /// (per D10 — no compound index needed).
  ///
  /// REQ-COACH-DISC-DATA-004, REQ-COACH-DISC-DATA-005.
  Future<List<TrainerPublicProfile>> listByGeohashPrefix(
    String prefix5, {
    TrainerSpecialty? specialty,
  }) async {
    final end = '$prefix5$_upperBoundSuffix';

    final snap = await _col
        .where('trainerGeohash', isGreaterThanOrEqualTo: prefix5)
        .where('trainerGeohash', isLessThan: end)
        .get();

    var results =
        snap.docs.map((d) => TrainerPublicProfile.fromJson(d.data())).toList();

    if (specialty != null) {
      results = results.where((t) => t.trainerSpecialty == specialty).toList();
    }

    return results;
  }

  /// Returns all trainers ordered by `displayNameLowercase` ASC, limit 50.
  ///
  /// If [specialty] is provided, the result is filtered client-side (D10).
  ///
  /// REQ-COACH-DISC-DATA-006.
  Future<List<TrainerPublicProfile>> listAll({
    TrainerSpecialty? specialty,
  }) async {
    final snap = await _col.orderBy('displayNameLowercase').limit(50).get();

    var results =
        snap.docs.map((d) => TrainerPublicProfile.fromJson(d.data())).toList();

    if (specialty != null) {
      results = results.where((t) => t.trainerSpecialty == specialty).toList();
    }

    return results;
  }

  /// Returns the [TrainerPublicProfile] for [uid], or `null` if no doc exists.
  ///
  /// REQ-COACH-DISC-DATA-007.
  Future<TrainerPublicProfile?> getById(String uid) async {
    final snap = await _col.doc(uid).get();
    final data = snap.data();
    if (!snap.exists || data == null) return null;
    return TrainerPublicProfile.fromJson(data);
  }
}
