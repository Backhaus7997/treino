import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/payments/data/payment_repository.dart';
import 'package:treino/features/payments/domain/payment.dart';

// Net-new test for PaymentRepository.markManyPaid: the suelto confirmation
// flow used to loop markPaid per id sequentially, leaving a half-paid state if
// one write failed mid-way. markManyPaid must flip every doc atomically via a
// single WriteBatch. Mirrors the data-layer pattern in payments_gap_test.dart.

const _trainerId = 'tA';

Payment _pending({
  required String id,
  int amountArs = 1500,
  String concept = 'Clase suelta',
}) =>
    Payment(
      id: id,
      trainerId: _trainerId,
      athleteId: 'aA',
      amountArs: amountArs,
      concept: concept,
      status: PaymentStatus.pending,
      createdAt: DateTime.utc(2026, 6, 16),
    );

void main() {
  group('PaymentRepository.markManyPaid', () {
    late FakeFirebaseFirestore firestore;
    late PaymentRepository repo;

    setUp(() {
      firestore = FakeFirebaseFirestore();
      repo = PaymentRepository(firestore: firestore);
    });

    test('flips all pending one-off docs to paid in one batch', () async {
      // Seed three pending one-off charges with deterministic ids.
      for (final id in ['p1', 'p2', 'p3']) {
        await firestore.collection('payments').doc(id).set({
          ..._pending(id: id).toJson(),
          'id': id,
        });
      }

      final localPaidAt = DateTime(2026, 6, 16, 10, 0);
      await repo.markManyPaid(['p1', 'p2', 'p3'], localPaidAt);

      final expectedTs = Timestamp.fromDate(localPaidAt.toUtc());
      for (final id in ['p1', 'p2', 'p3']) {
        final data =
            (await firestore.collection('payments').doc(id).get()).data()!;
        expect(data['status'], equals('paid'), reason: 'doc $id status');
        expect(data['paidAt'], equals(expectedTs), reason: 'doc $id paidAt');
        // Unrelated fields untouched.
        expect(data['trainerId'], equals(_trainerId));
        expect(data['athleteId'], equals('aA'));
      }
    });

    test('is a no-op when the id list is empty', () async {
      await firestore.collection('payments').doc('p1').set({
        ..._pending(id: 'p1').toJson(),
        'id': 'p1',
      });

      await repo.markManyPaid(const [], DateTime.utc(2026, 6, 16));

      final data =
          (await firestore.collection('payments').doc('p1').get()).data()!;
      // Untouched: still pending, no paidAt written.
      expect(data['status'], equals('pending'));
      expect(data['paidAt'], isNull);
    });
  });
}
