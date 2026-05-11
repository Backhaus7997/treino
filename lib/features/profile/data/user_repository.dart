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

  CollectionReference<Map<String, Object?>> get _users =>
      _firestore.collection('users');

  Future<UserProfile> getOrCreate({
    required String uid,
    required String email,
    required String displayName,
  }) async {
    final existing = await get(uid);
    if (existing != null) return existing;
    final now = DateTime.now().toUtc();
    final profile = UserProfile(
      uid: uid,
      email: email,
      displayName: displayName,
      role: UserRole.athlete,
      createdAt: now,
      updatedAt: now,
    );
    await _users.doc(uid).set(profile.toJson());
    return profile;
  }

  Future<void> createIfAbsent({
    required String uid,
    required String email,
    required String displayName,
  }) async {
    final snap = await _users.doc(uid).get();
    if (snap.exists) return;
    final now = DateTime.now().toUtc();
    final profile = UserProfile(
      uid: uid,
      email: email,
      displayName: displayName,
      role: UserRole.athlete,
      createdAt: now,
      updatedAt: now,
    );
    await _users.doc(uid).set(profile.toJson(), SetOptions(merge: true));
  }

  Future<UserProfile?> get(String uid) async {
    final snap = await _users.doc(uid).get();
    final data = snap.data();
    if (!snap.exists || data == null) return null;
    return UserProfile.fromJson(data);
  }

  /// Partial update. Immutable fields are filtered out defensively.
  /// `updatedAt` is always overwritten — callers do not set it.
  Future<void> update(String uid, Map<String, Object?> partial) async {
    final sanitized = Map<String, Object?>.fromEntries(
      partial.entries.where((e) => !_immutableFields.contains(e.key)),
    )..['updatedAt'] = Timestamp.fromDate(DateTime.now().toUtc());
    await _users.doc(uid).set(sanitized, SetOptions(merge: true));
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
