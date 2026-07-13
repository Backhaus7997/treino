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
import 'package:treino/features/workout/domain/session.dart';
import 'package:treino/features/workout/domain/session_status.dart';

// Slice 1 (2026-07) — payments decoupled from training, made 100% manual.
//
// This file used to prove the porSesion `acceptedAt` floor (a HIGH-severity
// bug in the now-removed per-session virtual-charge logic). That logic is
// gone: [miCuotaProvider] no longer watches Sessions or the billing
// cadence/rate at all — it only reads real `Payment` docs.
//
// These tests instead prove the DEcoupling: even when a `porSesion` billing
// config exists and the athlete has finished sessions (data that used to
// synthesize a per-session charge), the provider's output is completely
// unaffected by them. `athleteBillingPairProvider` / `sessionsByUidProvider`
// are still overridden in the harness on purpose — to show that feeding them
// data which would have produced a charge under the old logic changes
// nothing here.

const _trainerId = 'tA';
const _athleteId = 'aA';

TrainerLink _link({DateTime? acceptedAt}) => TrainerLink(
      id: 'link-1',
      trainerId: _trainerId,
      athleteId: _athleteId,
      status: TrainerLinkStatus.active,
      requestedAt: DateTime.utc(2026, 1, 1),
      acceptedAt: acceptedAt,
      sharedWithTrainer: true,
    );

Session _finished({required DateTime finishedAt}) => Session(
      id: 'sess-${finishedAt.millisecondsSinceEpoch}',
      uid: _athleteId,
      routineId: 'r1',
      routineName: 'Rutina',
      startedAt: finishedAt,
      finishedAt: finishedAt,
      status: SessionStatus.finished,
    );

ProviderContainer _container({
  required TrainerLink link,
  required List<Payment> payments,
  AthleteBilling? billing,
  List<Session> sessions = const [],
}) {
  final container = ProviderContainer(
    overrides: [
      currentAthleteLinkProvider.overrideWith((ref) async => link),
      athletePaymentsProvider.overrideWith((ref) => Stream.value(payments)),
      // miCuotaProvider no longer reads either of these — they're overridden
      // here purely to prove the tests below are unaffected by them.
      athleteBillingPairProvider.overrideWith(
        (ref, pair) => Stream.value(billing),
      ),
      sessionsByUidProvider.overrideWith((ref, uid) async => sessions),
    ],
  );
  return container;
}

/// Reads [miCuotaProvider] after letting every upstream async dependency
/// resolve, so the synchronous folding inside the provider sees `data`.
Future<MiCuotaState?> _readSettled(ProviderContainer container) async {
  await container.read(currentAthleteLinkProvider.future);
  await container.read(athletePaymentsProvider.future);
  return container.read(miCuotaProvider).valueOrNull;
}

void main() {
  group('miCuotaProvider — no auto-generation from cadence/sessions', () {
    test(
      'porSesion config + finished sessions, no real Payment → 0 computed '
      'items (charge is NOT synthesized from session count)',
      () async {
        final acceptedAt = DateTime.utc(2026, 6, 1);
        final container = _container(
          link: _link(acceptedAt: acceptedAt),
          billing: AthleteBilling(
            trainerId: _trainerId,
            athleteId: _athleteId,
            amountArs: 3000,
            cadence: BillingCadence.porSesion,
            updatedAt: acceptedAt,
          ),
          payments: const [], // trainer never registered a real charge
          sessions: [
            _finished(finishedAt: DateTime.utc(2026, 6, 2)),
            _finished(finishedAt: DateTime.utc(2026, 6, 9)),
            _finished(finishedAt: DateTime.utc(2026, 6, 16)),
          ],
        );
        addTearDown(container.dispose);

        final state = await _readSettled(container);

        expect(state, isNotNull);
        expect(state!.items, isEmpty);
        expect(state.totalArs, equals(0));
      },
    );

    test(
      'porSesion config + finished sessions + a real pending Payment → only '
      'the real Payment surfaces (amount is the doc amount, NOT sessions × rate)',
      () async {
        final container = _container(
          link: _link(acceptedAt: DateTime.utc(2026, 1, 1)),
          billing: AthleteBilling(
            trainerId: _trainerId,
            athleteId: _athleteId,
            amountArs: 3000,
            cadence: BillingCadence.porSesion,
            updatedAt: DateTime.utc(2026, 1, 1),
          ),
          payments: [
            Payment(
              id: 'p1',
              trainerId: _trainerId,
              athleteId: _athleteId,
              amountArs: 5000,
              concept: 'Clase suelta',
              status: PaymentStatus.pending,
              createdAt: DateTime.utc(2026, 6, 1),
            ),
          ],
          sessions: [
            _finished(finishedAt: DateTime.utc(2026, 6, 2)),
            _finished(finishedAt: DateTime.utc(2026, 6, 9)),
          ],
        );
        addTearDown(container.dispose);

        final state = await _readSettled(container);

        expect(state, isNotNull);
        expect(state!.items, hasLength(1));
        expect(state.items.single.cadence, equals(BillingCadence.suelto));
        expect(state.items.single.amountArs, equals(5000));
        expect(state.items.single.concept, equals('Clase suelta'));
        // 5000 (the real doc), NOT 2 sessions × 3000 = 6000.
        expect(state.totalArs, equals(5000));
      },
    );
  });
}
