import 'package:cloud_firestore/cloud_firestore.dart'
    show CollectionReference, DocumentSnapshot, FieldValue, FirebaseFirestore;

import '../domain/routine.dart';

class RoutineRepository {
  RoutineRepository({required FirebaseFirestore firestore})
      : _firestore = firestore;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, Object?>> get _collection =>
      _firestore.collection('routines');

  Future<List<Routine>> listAll() async {
    final snap = await _collection.get();
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
    return snap.docs.map((d) => Routine.fromJson(d.data())).toList();
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

  Routine? _fromDoc(DocumentSnapshot<Map<String, Object?>> snap) {
    final data = snap.data();
    if (!snap.exists || data == null) return null;
    return Routine.fromJson(data);
  }
}
