import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart'
    show currentAthleteLinkProvider;
import 'package:treino/features/coach/domain/trainer_link.dart';
import 'package:treino/features/coach/domain/trainer_link_status.dart';
import 'package:treino/features/payments/application/billing_providers.dart'
    show athleteBillingPairProvider;
import 'package:treino/features/payments/application/mi_cuota_provider.dart';
import 'package:treino/features/payments/application/payment_providers.dart'
    show athletePaymentsProvider;
import 'package:treino/features/payments/domain/athlete_billing.dart';
import 'package:treino/features/payments/domain/payment.dart';
import 'package:treino/features/workout/application/session_providers.dart'
    show sessionsByUidProvider;

// Regression test for the HIGH-severity bug in [miCuotaProvider]: when a
// watched stream errored with no prior value, the loading guard
// (isLoading && !hasValue) was false, so the provider proceeded with
// `valueOrNull ?? const []` and emitted AsyncValue.data with incomplete data —
// hiding the failure from the athlete (e.g. an empty/partial cuota).
//
// The fix mirrors pagosPorCobrarProvider: a hasError && !hasValue branch after
// each ref.watch that re-emits AsyncValue.error.

const _trainerId = 'tB';
const _athleteId = 'aB';

TrainerLink _link() => TrainerLink(
      id: 'link-err',
      trainerId: _trainerId,
      athleteId: _athleteId,
      status: TrainerLinkStatus.active,
      requestedAt: DateTime.utc(2026, 1, 1),
      acceptedAt: DateTime.utc(2026, 1, 1),
      sharedWithTrainer: true,
    );

void main() {
  group('miCuotaProvider — stream error propagation', () {
    test(
      'propagates payments stream error instead of emitting empty data',
      () async {
        final container = ProviderContainer(
          overrides: [
            currentAthleteLinkProvider.overrideWith((ref) async => _link()),
            athletePaymentsProvider.overrideWith(
              (ref) => Stream<List<Payment>>.error(Exception('boom')),
            ),
            athleteBillingPairProvider.overrideWith(
              (ref, pair) => Stream<AthleteBilling?>.value(null),
            ),
            sessionsByUidProvider.overrideWith((ref, uid) async => const []),
          ],
        );
        addTearDown(container.dispose);

        await container.read(currentAthleteLinkProvider.future);
        // Let the payments stream surface its error.
        await container.read(athletePaymentsProvider.stream).first.then(
              (_) {},
              onError: (Object _) {},
            );

        final result = container.read(miCuotaProvider);

        expect(result.hasError, isTrue);
        expect(result.hasValue, isFalse);
      },
    );

    test(
      'propagates link stream error instead of emitting empty data',
      () async {
        final container = ProviderContainer(
          overrides: [
            currentAthleteLinkProvider.overrideWith(
              (ref) async => throw Exception('link boom'),
            ),
            athletePaymentsProvider.overrideWith(
              (ref) => Stream<List<Payment>>.value(const []),
            ),
            athleteBillingPairProvider.overrideWith(
              (ref, pair) => Stream<AthleteBilling?>.value(null),
            ),
            sessionsByUidProvider.overrideWith((ref, uid) async => const []),
          ],
        );
        addTearDown(container.dispose);

        await container.read(currentAthleteLinkProvider.future).then(
              (_) {},
              onError: (Object _) {},
            );

        final result = container.read(miCuotaProvider);

        expect(result.hasError, isTrue);
        expect(result.hasValue, isFalse);
      },
    );
  });
}
