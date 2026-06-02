import 'dart:developer' as developer;

import 'package:cloud_firestore/cloud_firestore.dart'
    show CollectionReference, DocumentSnapshot, FirebaseFirestore;

import '../domain/performance_test.dart';

class PerformanceTestRepository {
  PerformanceTestRepository({required FirebaseFirestore firestore})
      : _firestore = firestore;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, Object?>> get _collection =>
      _firestore.collection('performance_tests');

  // ─── add ────────────────────────────────────────────────────────────────

  /// Creates a new performance test document with an auto-generated id.
  /// Returns the saved model with the assigned id.
  Future<PerformanceTest> add(PerformanceTest t) async {
    final ref = _collection.doc();
    final withId = t.copyWith(id: ref.id);
    await ref.set(withId.toJson());
    return withId;
  }

  // ─── delete ─────────────────────────────────────────────────────────────

  Future<void> delete(String id) async {
    await _collection.doc(id).delete();
  }

  // ─── watchRecordedBy ────────────────────────────────────────────────────

  /// Live stream of all performance tests recorded by [trainerUid].
  /// Single-field query — no composite index required.
  /// Sort (recordedAt ascending) is done client-side.
  Stream<List<PerformanceTest>> watchRecordedBy(String trainerUid) {
    return _collection
        .where('recordedBy', isEqualTo: trainerUid)
        .snapshots()
        .map(
          (snap) =>
              snap.docs.map(_fromDoc).whereType<PerformanceTest>().toList(),
        );
  }

  // ─── watchForAthlete ────────────────────────────────────────────────────

  /// Live stream of all performance tests for [athleteId] (athlete's own view).
  /// Single-field query — no composite index required.
  Stream<List<PerformanceTest>> watchForAthlete(String athleteId) {
    return _collection.where('athleteId', isEqualTo: athleteId).snapshots().map(
          (snap) =>
              snap.docs.map(_fromDoc).whereType<PerformanceTest>().toList(),
        );
  }

  // ─── Private helpers ────────────────────────────────────────────────────

  PerformanceTest? _fromDoc(DocumentSnapshot<Map<String, Object?>> snap) {
    final data = snap.data();
    if (!snap.exists || data == null) return null;
    try {
      // Inject doc id so a doc that didn't persist `id` in its body still
      // decodes. Wrapped in try/catch so a single malformed doc can't break
      // the whole list (mirrors SessionRepository._sessionFromDoc).
      return PerformanceTest.fromJson({...data, 'id': snap.id});
    } catch (e, st) {
      developer.log(
        'PerformanceTestRepository: skipped unparseable performance_test ${snap.id}',
        error: e,
        stackTrace: st,
      );
      return null;
    }
  }
}
