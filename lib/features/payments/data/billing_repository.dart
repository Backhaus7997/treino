import 'dart:developer' as developer;

import 'package:cloud_firestore/cloud_firestore.dart'
    show CollectionReference, DocumentSnapshot, FirebaseFirestore, SetOptions;

import '../domain/athlete_billing.dart';

class BillingRepository {
  BillingRepository({required FirebaseFirestore firestore})
      : _firestore = firestore;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, Object?>> get _collection =>
      _firestore.collection('athlete_billing');

  String _docId(String trainerId, String athleteId) =>
      '${trainerId}_$athleteId';

  Future<void> setConfig(AthleteBilling billing) async {
    final id = _docId(billing.trainerId, billing.athleteId);
    await _collection.doc(id).set(billing.toJson(), SetOptions(merge: true));
  }

  Stream<AthleteBilling?> watch(String trainerId, String athleteId) {
    final id = _docId(trainerId, athleteId);
    return _collection.doc(id).snapshots().map(_fromDoc);
  }

  AthleteBilling? _fromDoc(DocumentSnapshot<Map<String, Object?>> snap) {
    final data = snap.data();
    if (!snap.exists || data == null) return null;
    try {
      return AthleteBilling.fromJson(data);
    } catch (e, st) {
      developer.log(
        'BillingRepository: skipped unparseable doc ${snap.id}',
        error: e,
        stackTrace: st,
      );
      return null;
    }
  }
}
