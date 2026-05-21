import 'package:cloud_firestore/cloud_firestore.dart'
    show CollectionReference, FirebaseFirestore;

import '../domain/check_in.dart';

/// Repository for the check-in sub-collection at `/users/{uid}/checkIns/{date}`.
///
/// Doc id is the local-date key (`CheckIn.dateKey(localDate)`) which provides
/// natural per-day deduplication — no unique constraint needed.
class CheckInRepository {
  CheckInRepository({required FirebaseFirestore firestore})
      : _firestore = firestore;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, Object?>> _col(String uid) =>
      _firestore.collection('users').doc(uid).collection('checkIns');

  /// Returns today's check-in for [uid], or null if no doc exists.
  /// Auth-gated at the provider layer; caller must pass an authenticated uid.
  Future<CheckIn?> getTodayForUser(String uid) async {
    final today = CheckIn.dateKey(DateTime.now().toLocal());
    final snap = await _col(uid).doc(today).get();
    final data = snap.data();
    if (!snap.exists || data == null) return null;
    return CheckIn.fromJson(data);
  }

  /// Creates today's check-in for [uid]. If a doc for today already exists,
  /// returns the existing doc without overwriting (idempotent).
  ///
  /// When [inGym] is false, [gymId] and [gymName] are stored as null.
  Future<CheckIn> createTodayCheckIn(
    String uid, {
    required bool inGym,
    String? gymId,
    String? gymName,
  }) async {
    final now = DateTime.now();
    final local = now.toLocal();
    final id = CheckIn.dateKey(local);
    final ref = _col(uid).doc(id);

    final existing = await ref.get();
    if (existing.exists && existing.data() != null) {
      return CheckIn.fromJson(existing.data()!);
    }

    final checkIn = CheckIn(
      uid: uid,
      date: id,
      checkedInAt: now.toUtc(),
      gymId: inGym ? gymId : null,
      gymName: inGym ? gymName : null,
    );

    await ref.set(checkIn.toJson());
    return checkIn;
  }
}
