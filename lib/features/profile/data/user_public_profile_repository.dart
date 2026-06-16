import 'package:cloud_firestore/cloud_firestore.dart'
    show CollectionReference, FieldPath, FirebaseFirestore, SetOptions;

import '../domain/user_public_profile.dart';

/// Repository for the `userPublicProfiles` collection.
///
/// Exposes only the three public operations:
///   - [get] — fetch a single profile by uid.
///   - [set] — write / merge a profile doc.
///   - [searchByDisplayName] — prefix-range query on `displayNameLowercase`.
///
/// Note: `fake_cloud_firestore` does NOT enforce Firestore security rules.
/// Permission coverage is provided by the T35-style manual emulator test
/// (SCENARIO-268..270). See design Section A.6.
class UserPublicProfileRepository {
  UserPublicProfileRepository({required FirebaseFirestore firestore})
      : _firestore = firestore;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, Object?>> get _col =>
      _firestore.collection('userPublicProfiles');

  /// Returns the profile for [uid], or `null` if no document exists.
  Future<UserPublicProfile?> get(String uid) async {
    final snap = await _col.doc(uid).get();
    final data = snap.data();
    if (!snap.exists || data == null) return null;
    return UserPublicProfile.fromJson(data);
  }

  /// Live stream of the public profile at `userPublicProfiles/{uid}`, or null
  /// when the doc does not exist. Mirrors [get] but streamed.
  Stream<UserPublicProfile?> watch(String uid) {
    return _col.doc(uid).snapshots().map((snap) {
      final data = snap.data();
      if (!snap.exists || data == null) return null;
      return UserPublicProfile.fromJson(data);
    });
  }

  /// Batch lookup of public profiles by uid, returned as a `uid -> profile`
  /// map. Missing docs are simply absent from the map. Empty input
  /// short-circuits without I/O.
  ///
  /// `whereIn` is capped at 30 values per query in Firestore, so the distinct
  /// uids are chunked defensively. Used to resolve many review authors in a
  /// handful of reads instead of one live listener per tile (avoids the
  /// per-tile N+1 listen pattern in the RESEÑAS section).
  Future<Map<String, UserPublicProfile>> getByIds(List<String> uids) async {
    if (uids.isEmpty) return const {};
    final distinct = uids.toSet().toList();
    const chunkSize = 30;
    final out = <String, UserPublicProfile>{};
    for (var i = 0; i < distinct.length; i += chunkSize) {
      final chunk = distinct.sublist(
        i,
        i + chunkSize > distinct.length ? distinct.length : i + chunkSize,
      );
      final snap =
          await _col.where(FieldPath.documentId, whereIn: chunk).get();
      for (final doc in snap.docs) {
        final data = doc.data();
        out[doc.id] = UserPublicProfile.fromJson(data);
      }
    }
    return out;
  }

  /// Writes [profile] to `userPublicProfiles/{profile.uid}` with merge
  /// semantics so partial updates do not overwrite existing fields.
  Future<void> set(UserPublicProfile profile) async {
    await _col.doc(profile.uid).set(profile.toJson(), SetOptions(merge: true));
  }

  /// Performs a partial merge write on `userPublicProfiles/{uid}` using only
  /// the provided [fields]. Existing fields NOT in [fields] are preserved.
  ///
  /// Used by cross-feature write paths (SessionRepository.finish,
  /// FriendshipRepository.accept/delete) to update counters without
  /// clobbering identity fields (displayName, avatarUrl, gymId) set by
  /// UserRepository. See ADR-WRS-12.
  Future<void> updateCounters(String uid, Map<String, Object?> fields) async {
    await _col.doc(uid).set(fields, SetOptions(merge: true));
  }

  /// Flips the trainer's `sharedTemplatesWithAthletes` flag. When `true`,
  /// the Firestore rule on `routines` lets any authenticated user read this
  /// trainer's `trainer-template` docs — the athlete client filters them by
  /// linked-trainer-uid for the visible list. When `false`, only the
  /// trainer themselves can read their templates (existing behaviour).
  Future<void> setSharedTemplatesWithAthletes(String uid, bool value) async {
    await _col.doc(uid).set(
      {'sharedTemplatesWithAthletes': value},
      SetOptions(merge: true),
    );
  }

  /// Returns up to [limit] profiles whose `displayNameLowercase` starts with
  /// the trimmed lowercase [query]. Returns an empty list when [query] is
  /// blank after trimming. No Firestore call is issued in that case.
  ///
  /// The prefix-range technique uses the Unicode replacement character `￿`
  /// as an upper bound so that `startAt(q) + endBefore(q + '￿')` covers
  /// every string that begins with [q].
  Future<List<UserPublicProfile>> searchByDisplayName(
    String query, {
    int limit = 20,
  }) async {
    final trimmed = query.trim().toLowerCase();
    if (trimmed.isEmpty) return const [];

    final end = '$trimmed￿';

    final snap = await _col
        .where('displayNameLowercase', isGreaterThanOrEqualTo: trimmed)
        .where('displayNameLowercase', isLessThan: end)
        .limit(limit)
        .get();

    return snap.docs.map((d) => UserPublicProfile.fromJson(d.data())).toList();
  }
}
