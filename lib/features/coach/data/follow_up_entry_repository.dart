import 'dart:developer' as developer;

import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/follow_up_entry.dart';

/// Repository de entradas de seguimiento privadas del PF sobre un alumno.
///
/// - Firestore: colección `follow_up_entries/{id}` con
///   `id = {trainerId}_{athleteId}_{timestamp}`.
/// - Query paginable por `(trainerId, athleteId, recordedAt DESC)` — requiere
///   composite index (declarado en `firestore.indexes.json`).
/// - Trainer-only en rules (ver `firestore.rules`).
class FollowUpEntryRepository {
  FollowUpEntryRepository({required FirebaseFirestore firestore})
      : _firestore = firestore;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, Object?>> get _collection =>
      _firestore.collection('follow_up_entries');

  String _docId(String trainerId, String athleteId, String timestamp) =>
      '${trainerId}_${athleteId}_$timestamp';

  /// Crea una nueva entrada. Devuelve el modelo con el id asignado.
  Future<FollowUpEntry> add({
    required String trainerId,
    required String athleteId,
    required String text,
    required FollowUpTag tag,
  }) async {
    final now = DateTime.now();
    final timestamp = now.microsecondsSinceEpoch.toString();
    final id = _docId(trainerId, athleteId, timestamp);
    final entry = FollowUpEntry(
      id: id,
      trainerId: trainerId,
      athleteId: athleteId,
      text: text,
      tag: tag,
      recordedAt: now,
    );
    await _collection.doc(id).set(entry.toJson());
    return entry;
  }

  /// Watch reactivo de las entradas del par PF↔alumno, DESC.
  Stream<List<FollowUpEntry>> watch(String trainerId, String athleteId) {
    return _collection
        .where('trainerId', isEqualTo: trainerId)
        .where('athleteId', isEqualTo: athleteId)
        .orderBy('recordedAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs
            .map(_fromDoc)
            .whereType<FollowUpEntry>()
            .toList(growable: false));
  }

  /// Actualiza texto y/o tag de una entrada existente. La rule exige que
  /// `trainerId`, `athleteId`, `recordedAt` no cambien — el caller pasa el
  /// mismo doc con los nuevos valores.
  Future<void> update(FollowUpEntry entry) async {
    await _collection.doc(entry.id).set(entry.toJson());
  }

  Future<void> delete(String id) async {
    await _collection.doc(id).delete();
  }

  FollowUpEntry? _fromDoc(QueryDocumentSnapshot<Map<String, Object?>> snap) {
    try {
      return FollowUpEntry.fromJson(snap.data());
    } catch (e, st) {
      developer.log(
        'FollowUpEntryRepository: skipped unparseable doc ${snap.id}',
        error: e,
        stackTrace: st,
      );
      return null;
    }
  }
}
