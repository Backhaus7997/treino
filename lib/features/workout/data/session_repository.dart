import 'package:cloud_firestore/cloud_firestore.dart'
    show CollectionReference, DocumentSnapshot, FirebaseFirestore, Timestamp;

import '../domain/session.dart';
import '../domain/session_status.dart';
import '../domain/set_log.dart';

class SessionRepository {
  SessionRepository({required FirebaseFirestore firestore})
      : _firestore = firestore;

  final FirebaseFirestore _firestore;

  // ─── Private collection getters ─────────────────────────────────────────

  CollectionReference<Map<String, Object?>> _sessions(String uid) =>
      _firestore.collection('users').doc(uid).collection('sessions');

  CollectionReference<Map<String, Object?>> _setLogs(
          String uid, String sessionId) =>
      _sessions(uid).doc(sessionId).collection('setLogs');

  // ─── create ─────────────────────────────────────────────────────────────

  Future<Session> create({
    required String uid,
    required String routineId,
    required String routineName,
    required DateTime startedAt,
    int dayNumber = 1,
  }) async {
    final ref = _sessions(uid).doc();
    final session = Session(
      id: ref.id,
      uid: uid,
      routineId: routineId,
      routineName: routineName,
      startedAt: startedAt,
      finishedAt: null,
      totalVolumeKg: 0.0,
      durationMin: 0,
      status: SessionStatus.active,
      dayNumber: dayNumber,
    );
    await ref.set(session.toJson());
    return session;
  }

  // ─── finish ─────────────────────────────────────────────────────────────

  Future<void> finish({
    required String uid,
    required String sessionId,
    required DateTime finishedAt,
    required double totalVolumeKg,
    required int durationMin,
    bool wasFullyCompleted = false,
  }) async {
    // finishedAt MUST be Timestamp.fromDate, not a raw DateTime — real Firestore
    // serializes a raw DateTime as an ISO string, but the @TimestampConverter
    // on Session.finishedAt expects a Firestore Timestamp on read. Without
    // this conversion, listByUid()/getActive() would fail to deserialize
    // sessions finished against production Firestore.
    await _sessions(uid).doc(sessionId).update({
      'status': SessionStatusX(SessionStatus.finished).toJson(),
      'finishedAt': Timestamp.fromDate(finishedAt.toUtc()),
      'totalVolumeKg': totalVolumeKg,
      'durationMin': durationMin,
      'wasFullyCompleted': wasFullyCompleted,
    });
  }

  // ─── getById ────────────────────────────────────────────────────────────

  Future<Session?> getById({
    required String uid,
    required String sessionId,
  }) async {
    final snap = await _sessions(uid).doc(sessionId).get();
    return _sessionFromDoc(snap);
  }

  // ─── listByUid ──────────────────────────────────────────────────────────

  Future<List<Session>> listByUid(String uid) async {
    final snap =
        await _sessions(uid).orderBy('startedAt', descending: true).get();
    return snap.docs.map(_sessionFromDoc).whereType<Session>().toList();
  }

  // ─── getActive ──────────────────────────────────────────────────────────

  Future<Session?> getActive(String uid) async {
    final snap = await _sessions(uid)
        .where('status', isEqualTo: 'active')
        .orderBy('startedAt', descending: true)
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    return _sessionFromDoc(snap.docs.first);
  }

  // ─── addSetLog ──────────────────────────────────────────────────────────

  Future<SetLog> addSetLog({
    required String uid,
    required String sessionId,
    required SetLog setLog,
  }) async {
    final ref = _setLogs(uid, sessionId).doc();
    final withId = setLog.copyWith(id: ref.id);
    await ref.set(withId.toJson());
    return withId;
  }

  // ─── listSetLogs ────────────────────────────────────────────────────────

  Future<List<SetLog>> listSetLogs({
    required String uid,
    required String sessionId,
  }) async {
    final snap = await _setLogs(uid, sessionId)
        .orderBy('setNumber', descending: false)
        .get();
    return snap.docs.map(_setLogFromDoc).whereType<SetLog>().toList();
  }

  // ─── Private helpers ────────────────────────────────────────────────────

  Session? _sessionFromDoc(DocumentSnapshot<Map<String, Object?>> snap) {
    final data = snap.data();
    if (!snap.exists || data == null) return null;
    return Session.fromJson(data);
  }

  SetLog? _setLogFromDoc(DocumentSnapshot<Map<String, Object?>> snap) {
    final data = snap.data();
    if (!snap.exists || data == null) return null;
    return SetLog.fromJson(data);
  }
}
