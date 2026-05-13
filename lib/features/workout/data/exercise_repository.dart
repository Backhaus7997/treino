import 'package:cloud_firestore/cloud_firestore.dart'
    show CollectionReference, DocumentSnapshot, FieldPath, FirebaseFirestore;

import '../domain/exercise.dart';

class ExerciseRepository {
  ExerciseRepository({required FirebaseFirestore firestore})
      : _firestore = firestore;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, Object?>> get _collection =>
      _firestore.collection('exercises');

  Future<List<Exercise>> listAll() async {
    final snap = await _collection.get();
    return snap.docs.map(_fromDoc).whereType<Exercise>().toList();
  }

  Future<Exercise?> getById(String id) async {
    final snap = await _collection.doc(id).get();
    return _fromDoc(snap);
  }

  /// Eager batch lookup. Empty input short-circuits without I/O.
  /// `whereIn` is capped at 30 values per query in Firestore; chunked
  /// defensively for future Fase 4 routines that may reference many exercises.
  Future<List<Exercise>> getByIds(List<String> ids) async {
    if (ids.isEmpty) return const [];
    const chunkSize = 30;
    final out = <Exercise>[];
    for (var i = 0; i < ids.length; i += chunkSize) {
      final chunk = ids.sublist(
        i,
        i + chunkSize > ids.length ? ids.length : i + chunkSize,
      );
      final snap = await _collection
          .where(FieldPath.documentId, whereIn: chunk)
          .get();
      out.addAll(snap.docs.map(_fromDoc).whereType<Exercise>());
    }
    return out;
  }

  Exercise? _fromDoc(DocumentSnapshot<Map<String, Object?>> snap) {
    final data = snap.data();
    if (!snap.exists || data == null) return null;
    return Exercise.fromJson(data);
  }
}
