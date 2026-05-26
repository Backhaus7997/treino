import 'package:cloud_firestore/cloud_firestore.dart'
    show CollectionReference, FirebaseFirestore, SetOptions;

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
