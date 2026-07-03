import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart'
    show trainerLinksStreamProvider;
import 'package:treino/features/coach/domain/trainer_link.dart';
import 'package:treino/features/coach/domain/trainer_link_status.dart';
import 'package:treino/features/payments/application/billing_providers.dart'
    show athleteBillingProvider;
import 'package:treino/features/payments/application/pagos_por_cobrar_provider.dart';
import 'package:treino/features/payments/application/payment_providers.dart'
    show trainerPaymentsProvider;
import 'package:treino/features/payments/domain/athlete_billing.dart';
import 'package:treino/features/payments/domain/payment.dart';

// TDD RED — REQ-VENC-12
//
// Coexistence gate: pagosPorCobrarProvider MUST NOT derive a virtual
// CobroPendiente for a period when ANY persisted Payment doc exists for
// (athleteId, periodKey) — regardless of the doc's status (pending OR paid).
//
// The current implementation only checks paid docs (alreadyPaid). These tests
// FAIL until the provider is updated to check hasDocForPeriod (any status).
//
// SCENARIO-VENC-12: ANY doc (including pending) for the period → skip virtual
// SCENARIO-VENC-13: no doc for period → virtual derived as normal

const _trainerId = 'tA';
const _athleteId = 'aA';

TrainerLink _activeLink() => TrainerLink(
      id: 'link-1',
      trainerId: _trainerId,
      athleteId: _athleteId,
      status: TrainerLinkStatus.active,
      requestedAt: DateTime.utc(2026, 1, 1),
      acceptedAt: DateTime.utc(2026, 1, 1),
      sharedWithTrainer: false,
    );

ProviderContainer _container({
  required List<Payment> payments,
  required AthleteBilling? billing,
}) {
  return ProviderContainer(
    overrides: [
      trainerLinksStreamProvider.overrideWith(
        (ref) => Stream.value([_activeLink()]),
      ),
      trainerPaymentsProvider.overrideWith(
        (ref) => Stream.value(payments),
      ),
      athleteBillingProvider.overrideWith(
        (ref, athleteId) => Stream.value(billing),
      ),
    ],
  );
}

Future<List<CobroPendiente>?> _readPagos(ProviderContainer container) async {
  await container.read(trainerLinksStreamProvider.future);
  await container.read(trainerPaymentsProvider.future);
  await container.read(athleteBillingProvider(_athleteId).future);
  return container.read(pagosPorCobrarProvider).valueOrNull;
}

void main() {
  final now = DateTime.now().toUtc();
  final monthKey = '${now.year}-${now.month.toString().padLeft(2, '0')}';

  final mensualBilling = AthleteBilling(
    trainerId: _trainerId,
    athleteId: _athleteId,
    amountArs: 8000,
    cadence: BillingCadence.mensual,
    updatedAt: now,
  );

  group('pagosPorCobrarProvider — coexistence gate (REQ-VENC-12)', () {
    // SCENARIO-VENC-12: existing PENDING doc for the period → no virtual derived
    test(
      'SCENARIO-VENC-12: pending persisted doc for period suppresses virtual CobroPendiente',
      () async {
        // A PENDING (not paid!) doc already exists for the current period.
        // Under the old code, alreadyPaid would be false → virtual would be added.
        // Under the new code, hasDocForPeriod → true → virtual suppressed.
        final existingPendingDoc = Payment(
          id: '${_trainerId}_${_athleteId}_$monthKey',
          trainerId: _trainerId,
          athleteId: _athleteId,
          amountArs: 8000,
          concept: 'Mensual Julio 2026',
          status: PaymentStatus.pending,
          periodKey: monthKey,
          createdAt: now,
        );

        final container = _container(
          payments: [existingPendingDoc],
          billing: mensualBilling,
        );
        addTearDown(container.dispose);

        final results = await _readPagos(container);

        expect(results, isNotNull);

        // The mensual virtual charge must NOT appear because a real doc
        // already exists for this periodKey (even though it's pending, not paid).
        final mensualCharges =
            results!.where((c) => c.cadence == BillingCadence.mensual).toList();
        expect(
          mensualCharges,
          isEmpty,
          reason:
              'A persisted pending doc for periodKey must suppress the virtual CobroPendiente',
        );
      },
    );

    // SCENARIO-VENC-12 variant: existing PAID doc for the period → also suppressed
    test(
      'SCENARIO-VENC-12 variant: paid persisted doc for period also suppresses virtual CobroPendiente',
      () async {
        final existingPaidDoc = Payment(
          id: '${_trainerId}_${_athleteId}_$monthKey',
          trainerId: _trainerId,
          athleteId: _athleteId,
          amountArs: 8000,
          concept: 'Mensual Julio 2026',
          status: PaymentStatus.paid,
          periodKey: monthKey,
          createdAt: now,
          paidAt: now,
        );

        final container = _container(
          payments: [existingPaidDoc],
          billing: mensualBilling,
        );
        addTearDown(container.dispose);

        final results = await _readPagos(container);

        expect(results, isNotNull);
        final mensualCharges =
            results!.where((c) => c.cadence == BillingCadence.mensual).toList();
        expect(mensualCharges, isEmpty);
      },
    );

    // SCENARIO-VENC-13: no persisted doc for period → virtual derived as normal
    test(
      'SCENARIO-VENC-13: no persisted doc for period → virtual CobroPendiente derived',
      () async {
        // Payments exist but for a DIFFERENT period key.
        final otherPeriodDoc = Payment(
          id: '${_trainerId}_${_athleteId}_2026-06',
          trainerId: _trainerId,
          athleteId: _athleteId,
          amountArs: 8000,
          concept: 'Mensual Junio 2026',
          status: PaymentStatus.paid,
          periodKey: '2026-06', // different period
          createdAt: DateTime.utc(2026, 6, 1),
          paidAt: DateTime.utc(2026, 6, 10),
        );

        final container = _container(
          payments: [otherPeriodDoc],
          billing: mensualBilling,
        );
        addTearDown(container.dispose);

        final results = await _readPagos(container);

        expect(results, isNotNull);

        // Current-period virtual charge MUST appear because no doc for monthKey exists.
        final mensualCharges =
            results!.where((c) => c.cadence == BillingCadence.mensual).toList();
        expect(
          mensualCharges,
          hasLength(1),
          reason:
              'No doc for current periodKey → virtual charge must be derived',
        );
        expect(mensualCharges.single.amountArs, equals(8000));
      },
    );
  });
}
