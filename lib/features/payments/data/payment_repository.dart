import 'dart:developer' as developer;

import 'package:cloud_firestore/cloud_firestore.dart'
    show CollectionReference, DocumentSnapshot, FirebaseFirestore, Timestamp;

import '../domain/payment.dart';

class PaymentRepository {
  PaymentRepository({required FirebaseFirestore firestore})
      : _firestore = firestore;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, Object?>> get _collection =>
      _firestore.collection('payments');

  /// Adds a new payment document with an auto-generated id.
  Future<void> add(Payment payment) async {
    final ref = _collection.doc();
    await ref.set({...payment.toJson(), 'id': ref.id});
  }

  /// Marks a payment as paid, setting status and paidAt.
  Future<void> markPaid(String id, DateTime paidAt) async {
    await _collection.doc(id).update({
      'status': 'paid',
      'paidAt': Timestamp.fromDate(paidAt.toUtc()),
    });
  }

  /// Marks every payment in [ids] as paid atomically.
  ///
  /// Uses a single write batch so all docs flip together or none do: a
  /// failure mid-way (network drop, or a concurrently deleted doc making the
  /// update fail) leaves no half-paid state. A no-op when [ids] is empty.
  Future<void> markManyPaid(List<String> ids, DateTime paidAt) async {
    if (ids.isEmpty) return;
    final batch = _firestore.batch();
    final paidAtTs = Timestamp.fromDate(paidAt.toUtc());
    for (final id in ids) {
      batch.update(_collection.doc(id), {
        'status': 'paid',
        'paidAt': paidAtTs,
      });
    }
    await batch.commit();
  }

  /// Live stream of all payments for [trainerId].
  /// Single-field query — no composite index required.
  Stream<List<Payment>> watchForTrainer(String trainerId) {
    return _collection.where('trainerId', isEqualTo: trainerId).snapshots().map(
          (snap) => snap.docs.map(_fromDoc).whereType<Payment>().toList(),
        );
  }

  /// Live stream of all payments for [athleteId].
  /// Single-field query — no composite index required.
  Stream<List<Payment>> watchForAthlete(String athleteId) {
    return _collection.where('athleteId', isEqualTo: athleteId).snapshots().map(
          (snap) => snap.docs.map(_fromDoc).whereType<Payment>().toList(),
        );
  }

  Payment? _fromDoc(DocumentSnapshot<Map<String, Object?>> snap) {
    final data = snap.data();
    if (!snap.exists || data == null) return null;
    try {
      return Payment.fromJson({...data, 'id': snap.id});
    } catch (e, st) {
      developer.log(
        'PaymentRepository: skipped unparseable payment ${snap.id}',
        error: e,
        stackTrace: st,
      );
      return null;
    }
  }
}
