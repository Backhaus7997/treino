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

  // Fields that, when present in an update partial, must be propagated to the
  // trainerPublicProfiles document. Per design D3.
  // `displayName` and `avatarUrl` are shared with _publicFields — they trigger
  // both userPublicProfiles AND trainerPublicProfiles dual-write.
  static const _trainerPublicFields = {
    'displayName',
    'avatarUrl',
    'trainerBio',
    'trainerSpecialty',
    'trainerGeohash',
    'trainerLatitude',
    'trainerLongitude',
    'trainerHourlyRate',
  };

  CollectionReference<Map<String, Object?>> get _users =>
      _firestore.collection('users');

  CollectionReference<Map<String, Object?>> get _userPublicProfiles =>
      _firestore.collection('userPublicProfiles');

  CollectionReference<Map<String, Object?>> get _trainerPublicProfiles =>
      _firestore.collection('trainerPublicProfiles');

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

  /// Builds a partial trainer-public update map from a raw update [partial].
  ///
  /// Returns `null` when no trainer-public-relevant fields are in [partial] —
  /// callers must skip the trainerPublicProfiles write in that case.
  ///
  /// Per design D2: key-presence trigger (NOT value diff).
  /// Per design D1: field set includes displayName, avatarUrl, trainerBio,
  ///   trainerSpecialty, trainerGeohash, trainerLatitude, trainerLongitude,
  ///   trainerHourlyRate. `displayNameLowercase` is always derived when
  ///   `displayName` is present.
  ///
  /// REQ-COACH-DISC-DUAL-001.
  Map<String, Object?>? _trainerPublicSubsetFromPartial(
    Map<String, Object?> partial,
  ) {
    final hasTrainerField =
        partial.keys.any((k) => _trainerPublicFields.contains(k));
    if (!hasTrainerField) return null;

    final result = <String, Object?>{};
    if (partial.containsKey('displayName')) {
      final name = partial['displayName'] as String?;
      result['displayName'] = name;
      result['displayNameLowercase'] = name?.trim().toLowerCase();
    }
    if (partial.containsKey('avatarUrl')) {
      result['avatarUrl'] = partial['avatarUrl'];
    }
    if (partial.containsKey('trainerBio')) {
      result['trainerBio'] = partial['trainerBio'];
    }
    if (partial.containsKey('trainerSpecialty')) {
      result['trainerSpecialty'] = partial['trainerSpecialty'];
    }
    if (partial.containsKey('trainerGeohash')) {
      result['trainerGeohash'] = partial['trainerGeohash'];
    }
    if (partial.containsKey('trainerLatitude')) {
      result['trainerLatitude'] = partial['trainerLatitude'];
    }
    if (partial.containsKey('trainerLongitude')) {
      result['trainerLongitude'] = partial['trainerLongitude'];
    }
    if (partial.containsKey('trainerHourlyRate')) {
      result['trainerHourlyRate'] = partial['trainerHourlyRate'];
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
  ///
  /// Dual-write strategy (atomic WriteBatch):
  ///   - `users/{uid}` — always written.
  ///   - `userPublicProfiles/{uid}` — written when partial contains any of
  ///     `displayName`, `avatarUrl`, `gymId`. REQ-UPP-011, REQ-UPP-012.
  ///   - `trainerPublicProfiles/{uid}` — written when partial contains any of
  ///     the D3 trainer public fields. REQ-COACH-DISC-DUAL-001.
  ///
  /// All three writes are in a single batch.commit() — no partial state.
  Future<void> update(String uid, Map<String, Object?> partial) async {
    final sanitized = Map<String, Object?>.fromEntries(
      partial.entries.where((e) => !_immutableFields.contains(e.key)),
    )..['updatedAt'] = Timestamp.fromDate(DateTime.now().toUtc());

    final publicSubset = _publicSubsetFromPartial(partial);
    final trainerPublicSubset = _trainerPublicSubsetFromPartial(partial);

    if (publicSubset == null && trainerPublicSubset == null) {
      // No public-relevant fields — single write to users only.
      await _users.doc(uid).set(sanitized, SetOptions(merge: true));
      return;
    }

    final batch = _firestore.batch();
    batch.set(_users.doc(uid), sanitized, SetOptions(merge: true));

    if (publicSubset != null) {
      batch.set(
        _userPublicProfiles.doc(uid),
        publicSubset,
        SetOptions(merge: true),
      );
    }

    if (trainerPublicSubset != null) {
      batch.set(
        _trainerPublicProfiles.doc(uid),
        trainerPublicSubset,
        SetOptions(merge: true),
      );
    }

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
