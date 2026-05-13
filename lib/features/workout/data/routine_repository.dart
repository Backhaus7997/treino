import 'package:cloud_firestore/cloud_firestore.dart'
    show CollectionReference, DocumentSnapshot, FirebaseFirestore;

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

  Routine? _fromDoc(DocumentSnapshot<Map<String, Object?>> snap) {
    final data = snap.data();
    if (!snap.exists || data == null) return null;
    return Routine.fromJson(data);
  }
}
