import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/coach_hub/presentation/sections/pagos/widgets/pagos_buckets_provider.dart';
import 'package:treino/features/payments/application/payment_providers.dart'
    show trainerPaymentsProvider;
import 'package:treino/features/payments/domain/payment.dart';

// TDD RED — REQ-VENC-11
//
// Vencido bucket derivation:
//   - dueAt-based path:  status==pending && dueAt != null && dueAt.toUtc().isBefore(now)
//   - legacy null-dueAt: status==pending && dueAt == null && createdAt.toUtc().isBefore(periodStart)
//
// SCENARIO-VENC-08: past dueAt → Vencido
// SCENARIO-VENC-09: future dueAt → NOT Vencido (porVencer)
// SCENARIO-VENC-10: null dueAt + createdAt before month-start → Vencido (legacy)
// SCENARIO-VENC-11: null dueAt + createdAt same month → NOT Vencido (legacy)
//
// These tests will FAIL until pagos_buckets_provider.dart is updated with the
// new Vencido predicate that checks dueAt first.

const _trainerId = 'tA';

Payment _pendingWithDueAt({
  required String id,
  required DateTime createdAt,
  DateTime? dueAt,
}) =>
    Payment(
      id: id,
      trainerId: _trainerId,
      athleteId: 'aA',
      amountArs: 5000,
      concept: 'Mensual',
      status: PaymentStatus.pending,
      periodKey: '2026-07',
      createdAt: createdAt,
      dueAt: dueAt,
    );

ProviderContainer _containerWithPayments(List<Payment> payments) {
  return ProviderContainer(
    overrides: [
      trainerPaymentsProvider.overrideWith((ref) => Stream.value(payments)),
    ],
  );
}

Future<PagosBuckets?> _readBuckets(ProviderContainer container) async {
  await container.read(trainerPaymentsProvider.future);
  return container.read(pagosBucketsProvider).valueOrNull;
}

void main() {
  // Reference time: we use concrete dates so tests are deterministic.
  // The provider uses DateTime.now().toUtc() internally, so we set dueAt
  // relative to that.
  final now = DateTime.now().toUtc();
  final pastDueAt = now.subtract(const Duration(days: 1));
  final futureDueAt = now.add(const Duration(days: 30));
  // A createdAt clearly before the start of this month.
  final oldCreatedAt =
      DateTime.utc(now.year, now.month, 1).subtract(const Duration(days: 10));
  // A createdAt within the current month.
  final thisMonthCreatedAt = DateTime.utc(now.year, now.month, 1);

  group('pagosBucketsProvider — Vencido derivation (REQ-VENC-11)', () {
    // SCENARIO-VENC-08
    test(
      'SCENARIO-VENC-08: pending payment with past dueAt → Vencido bucket',
      () async {
        final payment = _pendingWithDueAt(
          id: 'p-past-due',
          createdAt:
              thisMonthCreatedAt, // createdAt is current month (would NOT be vencido under legacy rule)
          dueAt: pastDueAt, // dueAt is past → should be vencido
        );

        final container = _containerWithPayments([payment]);
        addTearDown(container.dispose);

        final buckets = await _readBuckets(container);

        expect(buckets, isNotNull);
        expect(
          buckets!.vencidos.map((p) => p.id),
          contains('p-past-due'),
          reason: 'Past dueAt with current-month createdAt must be in vencidos',
        );
        expect(
          buckets.porVencer.map((p) => p.id),
          isNot(contains('p-past-due')),
        );
      },
    );

    // SCENARIO-VENC-09
    test(
      'SCENARIO-VENC-09: pending payment with future dueAt → porVencer bucket',
      () async {
        final payment = _pendingWithDueAt(
          id: 'p-future-due',
          createdAt:
              oldCreatedAt, // old createdAt (legacy would call this vencido)
          dueAt: futureDueAt, // dueAt is future → NOT vencido
        );

        final container = _containerWithPayments([payment]);
        addTearDown(container.dispose);

        final buckets = await _readBuckets(container);

        expect(buckets, isNotNull);
        expect(
          buckets!.porVencer.map((p) => p.id),
          contains('p-future-due'),
          reason: 'Future dueAt must be in porVencer, NOT vencidos',
        );
        expect(
          buckets.vencidos.map((p) => p.id),
          isNot(contains('p-future-due')),
        );
      },
    );

    // SCENARIO-VENC-10
    test(
      'SCENARIO-VENC-10: null dueAt + createdAt before month-start → Vencido (legacy)',
      () async {
        final payment = _pendingWithDueAt(
          id: 'p-legacy-old',
          createdAt:
              oldCreatedAt, // before current month → vencido under legacy rule
          dueAt: null, // no dueAt → legacy path
        );

        final container = _containerWithPayments([payment]);
        addTearDown(container.dispose);

        final buckets = await _readBuckets(container);

        expect(buckets, isNotNull);
        expect(
          buckets!.vencidos.map((p) => p.id),
          contains('p-legacy-old'),
          reason: 'Null-dueAt + old createdAt must use legacy vencido rule',
        );
        expect(
          buckets.porVencer.map((p) => p.id),
          isNot(contains('p-legacy-old')),
        );
      },
    );

    // SCENARIO-VENC-11
    test(
      'SCENARIO-VENC-11: null dueAt + createdAt this month → NOT Vencido (legacy)',
      () async {
        final payment = _pendingWithDueAt(
          id: 'p-legacy-new',
          createdAt: thisMonthCreatedAt, // current month → not vencido
          dueAt: null, // no dueAt → legacy path
        );

        final container = _containerWithPayments([payment]);
        addTearDown(container.dispose);

        final buckets = await _readBuckets(container);

        expect(buckets, isNotNull);
        expect(
          buckets!.porVencer.map((p) => p.id),
          contains('p-legacy-new'),
          reason: 'Null-dueAt + this-month createdAt must NOT be vencido',
        );
        expect(
          buckets.vencidos.map((p) => p.id),
          isNot(contains('p-legacy-new')),
        );
      },
    );
  });
}
