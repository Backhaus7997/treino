import 'package:cloud_firestore/cloud_firestore.dart'
    show CollectionReference, FirebaseFirestore, SetOptions, Timestamp;

import '../domain/user_profile.dart';
import '../domain/user_role.dart';

class UserRepository {
  UserRepository({required FirebaseFirestore firestore})
      : _firestore = firestore;

  final FirebaseFirestore _firestore;

  // Fields that must never be mutated by client code (mirrors firestore.rules).
  static const _immutableFields = {'uid', 'role', 'email', 'createdAt'};

  // Fields that, when present in an update partial, must be propagated to the
  // userPublicProfiles document.
  static const _publicFields = {'displayName', 'avatarUrl', 'gymId'};

  CollectionReference<Map<String, Object?>> get _users =>
      _firestore.collection('users');

  CollectionReference<Map<String, Object?>> get _userPublicProfiles =>
      _firestore.collection('userPublicProfiles');

  // ---------------------------------------------------------------------------
  // Private helpers — REQ-UPP-002 / ADR-UPP-11
  // Callers MUST NOT pass displayNameLowercase — it is always derived here.
  // ---------------------------------------------------------------------------

  /// Builds the full public subset from a [UserProfile], deriving
  /// `displayNameLowercase` automatically.
  Map<String, Object?> _publicSubsetFromProfile(UserProfile profile) {
    return {
      'uid': profile.uid,
      'displayName': profile.displayName,
      'displayNameLowercase': profile.displayName?.trim().toLowerCase(),
      'avatarUrl': profile.avatarUrl,
      'gymId': profile.gymId,
    };
  }

  /// Builds a partial public update map from a raw update [partial], deriving
  /// `displayNameLowercase` when `displayName` is present. Returns `null` when
  /// no public-relevant fields (`displayName`, `avatarUrl`, `gymId`) are in
  /// [partial] — callers must skip the public write in that case.
  Map<String, Object?>? _publicSubsetFromPartial(
    Map<String, Object?> partial,
  ) {
    final hasPublicField = partial.keys.any((k) => _publicFields.contains(k));
    if (!hasPublicField) return null;

    final result = <String, Object?>{};
    if (partial.containsKey('displayName')) {
      final name = partial['displayName'] as String?;
      result['displayName'] = name;
      result['displayNameLowercase'] = name?.trim().toLowerCase();
    }
    if (partial.containsKey('avatarUrl')) {
      result['avatarUrl'] = partial['avatarUrl'];
    }
    if (partial.containsKey('gymId')) {
      result['gymId'] = partial['gymId'];
    }
    return result;
  }

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Creates the `users/{uid}` doc if missing, with `displayName: null`.
  /// Atomically also creates `userPublicProfiles/{uid}` in the same batch.
  /// REQ-UPP-009.
  Future<UserProfile> getOrCreate({
    required String uid,
    required String email,
  }) async {
    final existing = await get(uid);
    if (existing != null) return existing;
    final now = DateTime.now().toUtc();
    final profile = UserProfile(
      uid: uid,
      email: email,
      displayName: null,
      role: UserRole.athlete,
      createdAt: now,
      updatedAt: now,
    );

    final batch = _firestore.batch();
    batch.set(_users.doc(uid), profile.toJson());
    batch.set(
      _userPublicProfiles.doc(uid),
      _publicSubsetFromProfile(profile),
      SetOptions(merge: true),
    );
    await batch.commit();

    return profile;
  }

  /// Best-effort backfill on sign-in. Creates the doc with `displayName: null`
  /// and atomically also creates/updates `userPublicProfiles/{uid}`.
  /// REQ-UPP-010.
  Future<void> createIfAbsent({
    required String uid,
    required String email,
  }) async {
    final snap = await _users.doc(uid).get();
    if (snap.exists) return;
    final now = DateTime.now().toUtc();
    final profile = UserProfile(
      uid: uid,
      email: email,
      displayName: null,
      role: UserRole.athlete,
      createdAt: now,
      updatedAt: now,
    );

    final batch = _firestore.batch();
    batch.set(_users.doc(uid), profile.toJson(), SetOptions(merge: true));
    batch.set(
      _userPublicProfiles.doc(uid),
      _publicSubsetFromProfile(profile),
      SetOptions(merge: true),
    );
    await batch.commit();
  }

  Future<UserProfile?> get(String uid) async {
    final snap = await _users.doc(uid).get();
    final data = snap.data();
    if (!snap.exists || data == null) return null;
    return UserProfile.fromJson(data);
  }

  /// Partial update. Immutable fields are filtered out defensively.
  /// `updatedAt` is always overwritten — callers do not set it.
  /// When `displayName`, `avatarUrl`, or `gymId` are present in [partial],
  /// `userPublicProfiles/{uid}` is also updated in the same batch.
  /// REQ-UPP-011, REQ-UPP-012.
  Future<void> update(String uid, Map<String, Object?> partial) async {
    final sanitized = Map<String, Object?>.fromEntries(
      partial.entries.where((e) => !_immutableFields.contains(e.key)),
    )..['updatedAt'] = Timestamp.fromDate(DateTime.now().toUtc());

    final publicSubset = _publicSubsetFromPartial(partial);

    if (publicSubset == null) {
      // No public-relevant fields — single write to users only.
      await _users.doc(uid).set(sanitized, SetOptions(merge: true));
      return;
    }

    final batch = _firestore.batch();
    batch.set(_users.doc(uid), sanitized, SetOptions(merge: true));
    batch.set(
      _userPublicProfiles.doc(uid),
      publicSubset,
      SetOptions(merge: true),
    );
    await batch.commit();
  }

  Stream<UserProfile?> watch(String uid) {
    return _users.doc(uid).snapshots().map((snap) {
      final data = snap.data();
      if (!snap.exists || data == null) return null;
      return UserProfile.fromJson(data);
    });
  }

  Future<void> delete(String uid) async {
    throw UnsupportedError(
      'UserRepository.delete is not allowed from client code. '
      'Account deletion goes through a privileged Cloud Function.',
    );
  }
}
