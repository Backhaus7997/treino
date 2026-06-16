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

// Regression test for the payments-stream error bug: if trainerPaymentsProvider
// errors with no prior value, the provider previously fell back to an empty
// payments list, which made the "already paid" logic treat every athlete as
// never paid and re-surface their full recurring charge. The fix surfaces the
// error so the dashboard shows its error state instead of wrong amounts.

const _trainerId = 'tA';

TrainerLink _activeLink({String athleteId = 'aA'}) => TrainerLink(
      id: 'link-$athleteId',
      trainerId: _trainerId,
      athleteId: athleteId,
      status: TrainerLinkStatus.active,
      requestedAt: DateTime.utc(2026, 1, 1),
      acceptedAt: DateTime.utc(2026, 1, 1),
      sharedWithTrainer: true,
    );

void main() {
  test(
    'payments-stream error surfaces as error (does NOT re-surface charges)',
    () async {
      final now = DateTime.now().toUtc();

      final container = ProviderContainer(
        overrides: [
          trainerLinksStreamProvider
              .overrideWith((ref) => Stream.value([_activeLink()])),
          // Payments stream fails with NO prior value (offline/permission blip).
          trainerPaymentsProvider
              .overrideWith((ref) => Stream.error(StateError('boom'))),
          athleteBillingProvider.overrideWith(
            (ref, athleteId) => Stream.value(
              AthleteBilling(
                trainerId: _trainerId,
                athleteId: athleteId,
                amountArs: 7000,
                cadence: BillingCadence.mensual,
                updatedAt: now,
              ),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      // Settle the upstream streams.
      await container.read(trainerLinksStreamProvider.future);
      await expectLater(
        container.read(trainerPaymentsProvider.future),
        throwsA(isA<StateError>()),
      );

      final async = container.read(pagosPorCobrarProvider);

      // Must propagate the error, not fall back to data with a re-surfaced
      // mensual charge.
      expect(async.hasError, isTrue);
      expect(async.error, isA<StateError>());
      expect(async.valueOrNull, isNull);
    },
  );
}
