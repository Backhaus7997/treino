import 'package:cloud_firestore/cloud_firestore.dart'
    show CollectionReference, DocumentSnapshot, FieldValue, FirebaseFirestore;

import '../domain/routine.dart';

class RoutineRepository {
  RoutineRepository({required FirebaseFirestore firestore})
      : _firestore = firestore;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, Object?>> get _collection =>
      _firestore.collection('routines');

  /// Lists every public routine in the catalogue. Used by the Plantillas
  /// screen to render seed plans.
  ///
  /// The `where('visibility', isEqualTo: 'public')` filter is REQUIRED by
  /// firestore.rules: the read rule on `routines` checks
  /// `resource.data.visibility` per doc, so Firestore rejects list queries
  /// that don't constrain that field. Trainer-assigned (`private`) plans
  /// are fetched per-athlete via [listAssignedTo]; `shared` plans are
  /// explicitly excluded from Plantillas by design.
  ///
  /// Legacy seed routines that pre-date the visibility field are reconciled
  /// by `scripts/backfill_routines_source_visibility.js`.
  Future<List<Routine>> listAll() async {
    final snap =
        await _collection.where('visibility', isEqualTo: 'public').get();
    return snap.docs.map(_fromDoc).whereType<Routine>().toList();
  }

  Future<Routine?> getById(String id) async {
    final snap = await _collection.doc(id).get();
    return _fromDoc(snap);
  }

  /// Returns all plans assigned to [athleteId] by a trainer,
  /// ordered newest first (by `createdAt` DESC).
  ///
  /// Requires a composite index on `assignedTo + source + createdAt`
  /// (declared in `firestore.indexes.json`).
  ///
  /// REQ-COACH-PLANS-001, SCENARIO-432, SCENARIO-433.
  Future<List<Routine>> listAssignedTo(String athleteId) async {
    final snap = await _collection
        .where('assignedTo', isEqualTo: athleteId)
        .where('source', isEqualTo: 'trainer-assigned')
        .orderBy('createdAt', descending: true)
        .limit(20)
        .get();
    return snap.docs.map(_fromDoc).whereType<Routine>().toList();
  }

  /// Persists a trainer-assigned plan.
  ///
  /// Validations (client-side):
  /// - `routine.assignedBy` must be non-null and non-empty.
  /// - `routine.assignedTo` must be non-null and non-empty.
  ///
  /// The `id` field is removed from the JSON before calling `.add()` so
  /// Firestore generates the document id. `createdAt` is set to
  /// [FieldValue.serverTimestamp] at write time.
  ///
  /// Returns the saved [Routine] with its Firestore-generated [Routine.id].
  ///
  /// REQ-COACH-PLANS-002, SCENARIO-434, SCENARIO-435.
  Future<Routine> createAssigned(Routine routine) async {
    if (routine.assignedBy == null || routine.assignedBy!.isEmpty) {
      throw ArgumentError.value(
        routine.assignedBy,
        'assignedBy',
        'assignedBy must be a non-empty trainer uid',
      );
    }
    if (routine.assignedTo == null || routine.assignedTo!.isEmpty) {
      throw ArgumentError.value(
        routine.assignedTo,
        'assignedTo',
        'assignedTo must be a non-empty athlete uid',
      );
    }

    final json = routine.toJson()..remove('id');
    json['createdAt'] = FieldValue.serverTimestamp();
    final ref = await _collection.add(json);
    return routine.copyWith(id: ref.id);
  }

  /// Deserializes a Firestore doc into a [Routine], injecting the doc id.
  ///
  /// Trainer-assigned routines are written via `.add()` and do NOT carry an
  /// `id` field inside their data. Seeded plantillas DO have an `id` field
  /// (set explicitly by the seed script). Injecting `snap.id` unconditionally
  /// handles both cases: it overrides the existing value for seeds (same id)
  /// and supplies the missing field for trainer-assigned docs.
  Routine? _fromDoc(DocumentSnapshot<Map<String, Object?>> snap) {
    final data = snap.data();
    if (!snap.exists || data == null) return null;
    return Routine.fromJson({...data, 'id': snap.id});
  }
}
