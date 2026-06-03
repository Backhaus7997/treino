import 'dart:developer' as developer;

import 'package:cloud_firestore/cloud_firestore.dart'
    show CollectionReference, DocumentSnapshot, FirebaseFirestore, SetOptions;

import '../domain/athlete_note.dart';

class AthleteNoteRepository {
  AthleteNoteRepository({required FirebaseFirestore firestore})
      : _firestore = firestore;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, Object?>> get _collection =>
      _firestore.collection('athlete_notes');

  String _docId(String trainerId, String athleteId) =>
      '${trainerId}_$athleteId';

  Future<void> setNote(AthleteNote note) async {
    final id = _docId(note.trainerId, note.athleteId);
    await _collection.doc(id).set(note.toJson(), SetOptions(merge: true));
  }

  Stream<AthleteNote?> watch(String trainerId, String athleteId) {
    final id = _docId(trainerId, athleteId);
    return _collection.doc(id).snapshots().map(_fromDoc);
  }

  AthleteNote? _fromDoc(DocumentSnapshot<Map<String, Object?>> snap) {
    final data = snap.data();
    if (!snap.exists || data == null) return null;
    try {
      return AthleteNote.fromJson(data);
    } catch (e, st) {
      developer.log(
        'AthleteNoteRepository: skipped unparseable doc ${snap.id}',
        error: e,
        stackTrace: st,
      );
      return null;
    }
  }
}
