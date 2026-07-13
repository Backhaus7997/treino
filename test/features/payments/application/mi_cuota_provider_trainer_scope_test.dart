import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart'
    show currentAthleteLinkProvider;
import 'package:treino/features/coach/domain/trainer_link.dart';
import 'package:treino/features/coach/domain/trainer_link_status.dart';
import 'package:treino/features/payments/application/billing_providers.dart'
    show athleteBillingPairProvider;
import 'package:treino/features/payments/application/mi_cuota_provider.dart';
import 'package:treino/features/payments/application/pagos_por_cobrar_provider.dart'
    show argentinaNow;
import 'package:treino/features/payments/application/payment_providers.dart'
    show athletePaymentsProvider;
import 'package:treino/features/payments/domain/athlete_billing.dart';
import 'package:treino/features/payments/domain/payment.dart';
import 'package:treino/features/workout/application/session_providers.dart'
    show sessionsByUidProvider;

// Regression test: watchForAthlete filters payments by athleteId only, so
// athletePaymentsProvider streams every payment addressed to the athlete across
// ALL trainers — including a terminated link's. "Tu cuota" speaks only for the
// athlete's ACTIVE trainer, so miCuotaProvider must scope the stream by
// link.trainerId before folding it into cuota items. Without the filter a
// previous trainer's charge leaks in, attributed to the current trainer.

const _currentTrainerId = 'trainer-new';
const _oldTrainerId = 'trainer-old';
const _athleteId = 'aA';

TrainerLink _link() => TrainerLink(
      id: 'link-1',
      trainerId: _currentTrainerId,
      athleteId: _athleteId,
      status: TrainerLinkStatus.active,
      requestedAt: DateTime.utc(2026, 1, 1),
      acceptedAt: DateTime.utc(2026, 6, 1),
      sharedWithTrainer: true,
    );

ProviderContainer _container({
  required List<Payment> payments,
  AthleteBilling? billing,
}) =>
    ProviderContainer(
      overrides: [
        currentAthleteLinkProvider.overrideWith((ref) async => _link()),
        athletePaymentsProvider.overrideWith((ref) => Stream.value(payments)),
        athleteBillingPairProvider.overrideWith(
          (ref, pair) => Stream<AthleteBilling?>.value(billing),
        ),
        sessionsByUidProvider.overrideWith((ref, uid) async => const []),
      ],
    );

/// Reads [miCuotaProvider] after every upstream async dependency has settled,
/// so the synchronous folding inside the provider sees `data`.
Future<MiCuotaState?> _readSettled(ProviderContainer container) async {
  await container.read(currentAthleteLinkProvider.future);
  await container.read(athletePaymentsProvider.future);
  await container.read(
    athleteBillingPairProvider(
      (trainerId: _currentTrainerId, athleteId: _athleteId),
    ).future,
  );
  return container.read(miCuotaProvider).valueOrNull;
}

void main() {
  group('miCuotaProvider — active-trainer scope', () {
    test(
      'a pending charge from a previous trainer is excluded from "Tu cuota"',
      () async {
        final container = _container(
          // No recurring config — isolates the one-off pending path.
          billing: null,
          payments: [
            Payment(
              id: 'p-old',
              trainerId: _oldTrainerId,
              athleteId: _athleteId,
              amountArs: 5000,
              concept: 'Deuda con entrenador anterior',
              status: PaymentStatus.pending,
              createdAt: DateTime.utc(2026, 3, 10),
            ),
            Payment(
              id: 'p-new',
              trainerId: _currentTrainerId,
              athleteId: _athleteId,
              amountArs: 8000,
              concept: 'Clase suelta',
              status: PaymentStatus.pending,
              createdAt: DateTime.utc(2026, 6, 5),
            ),
          ],
        );
        addTearDown(container.dispose);

        final state = await _readSettled(container);

        expect(state, isNotNull);
        // Only the active trainer's pending charge, never the old one's.
        expect(state!.items, hasLength(1));
        expect(state.items.single.concept, equals('Clase suelta'));
        expect(state.totalArs, equals(8000));
      },
    );

    test(
      "a previous trainer's paid month does not settle the active mensual cuota",
      () async {
        // Match the month key the provider derives from argentinaNow().
        final now = argentinaNow();
        final monthKey = '${now.year}-${now.month.toString().padLeft(2, '0')}';

        final container = _container(
          billing: AthleteBilling(
            trainerId: _currentTrainerId,
            athleteId: _athleteId,
            amountArs: 12000,
            cadence: BillingCadence.mensual,
            updatedAt: DateTime.utc(2026, 6, 1),
          ),
          payments: [
            // Old trainer paid THIS month — must not satisfy the new trainer's
            // mensual charge.
            Payment(
              id: 'p-old-paid',
              trainerId: _oldTrainerId,
              athleteId: _athleteId,
              amountArs: 5000,
              concept: 'Mensual (anterior)',
              status: PaymentStatus.paid,
              periodKey: monthKey,
              createdAt: DateTime.utc(2026, 6, 1),
              paidAt: DateTime.utc(2026, 6, 2),
            ),
          ],
        );
        addTearDown(container.dispose);

        final state = await _readSettled(container);

        expect(state, isNotNull);
        final mensual = state!.items
            .where((i) => i.cadence == BillingCadence.mensual)
            .toList();
        // The active trainer's mensual charge stands: the old trainer's paid
        // payment was filtered out before the paid-check.
        expect(mensual, hasLength(1));
        expect(mensual.single.amountArs, equals(12000));
      },
    );
  });
}
