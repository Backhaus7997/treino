import 'dart:developer' as developer;

import 'package:cloud_firestore/cloud_firestore.dart'
    show CollectionReference, DocumentSnapshot, FirebaseFirestore;

import '../domain/measurement.dart';

class MeasurementRepository {
  MeasurementRepository({required FirebaseFirestore firestore})
      : _firestore = firestore;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, Object?>> get _collection =>
      _firestore.collection('measurements');

  // ─── add ────────────────────────────────────────────────────────────────

  /// Creates a new measurement document with an auto-generated id.
  /// Returns the saved model with the assigned id.
  Future<Measurement> add(Measurement m) async {
    final ref = _collection.doc();
    final withId = m.copyWith(id: ref.id);
    await ref.set(withId.toJson());
    return withId;
  }

  // ─── update ─────────────────────────────────────────────────────────────

  /// Actualiza los VALORES de una medición existente. La rule de Firestore
  /// exige que `recordedBy`, `athleteId` y el propio `id` NO cambien — el
  /// caller es responsable de pasar el mismo doc con los nuevos números y
  /// notes.
  Future<void> update(Measurement m) async {
    await _collection.doc(m.id).set(m.toJson());
  }

  // ─── delete ─────────────────────────────────────────────────────────────

  Future<void> delete(String id) async {
    await _collection.doc(id).delete();
  }

  // ─── watchRecordedBy ────────────────────────────────────────────────────

  /// Live stream of all measurements recorded by [trainerUid].
  /// Single-field query — no composite index required.
  /// Sort (recordedAt ascending) is done client-side.
  Stream<List<Measurement>> watchRecordedBy(String trainerUid) {
    return _collection
        .where('recordedBy', isEqualTo: trainerUid)
        .snapshots()
        .map(
          (snap) => snap.docs.map(_fromDoc).whereType<Measurement>().toList(),
        );
  }

  // ─── watchForAthlete ────────────────────────────────────────────────────

  /// Live stream of all measurements for [athleteId] (athlete's own view).
  /// Single-field query — no composite index required.
  ///
  /// Solo segura cuando el caller ES el atleta (`uid == athleteId`): un
  /// entrenador NO puede correrla porque las reglas exigen
  /// `recordedBy == uid || athleteId == uid` y esta query no garantiza la
  /// primera rama → Firestore deniega. Para el contexto de entrenador usar
  /// [watchForTrainerAthlete].
  Stream<List<Measurement>> watchForAthlete(String athleteId) {
    return _collection.where('athleteId', isEqualTo: athleteId).snapshots().map(
          (snap) => snap.docs.map(_fromDoc).whereType<Measurement>().toList(),
        );
  }

  // ─── watchForTrainerAthlete ─────────────────────────────────────────────

  /// Live stream de las mediciones que [trainerUid] registró para [athleteId].
  ///
  /// Dos igualdades (`recordedBy` + `athleteId`) — NO requiere índice compuesto.
  /// Satisface la regla de lectura vía `recordedBy == uid`, así que es la query
  /// correcta para el Coach Hub / detalle de alumno del entrenador. Sort
  /// (recordedAt ascending) se hace client-side.
  Stream<List<Measurement>> watchForTrainerAthlete(
    String trainerUid,
    String athleteId,
  ) {
    return _collection
        .where('recordedBy', isEqualTo: trainerUid)
        .where('athleteId', isEqualTo: athleteId)
        .snapshots()
        .map(
          (snap) => snap.docs.map(_fromDoc).whereType<Measurement>().toList(),
        );
  }

  // ─── Private helpers ────────────────────────────────────────────────────

  Measurement? _fromDoc(DocumentSnapshot<Map<String, Object?>> snap) {
    final data = snap.data();
    if (!snap.exists || data == null) return null;
    try {
      // Inject doc id so a doc that didn't persist `id` in its body still
      // decodes. Wrapped in try/catch so a single malformed doc can't break
      // the whole list (mirrors SessionRepository._sessionFromDoc).
      return Measurement.fromJson({...data, 'id': snap.id});
    } catch (e, st) {
      developer.log(
        'MeasurementRepository: skipped unparseable measurement ${snap.id}',
        error: e,
        stackTrace: st,
      );
      return null;
    }
  }
}
