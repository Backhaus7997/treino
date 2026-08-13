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
import 'package:treino/features/workout/application/session_providers.dart'
    show sessionsByUidProvider;
import 'package:treino/features/workout/domain/session.dart';
import 'package:treino/features/workout/domain/session_status.dart';

// Slice 1 (2026-07) — payments decoupled from training, made 100% manual.
//
// This file used to cover REQ-VENC-12 (the "coexistence gate": suppress a
// virtual mensual/semanal CobroPendiente once ANY persisted Payment doc
// exists for the period). That whole mechanism — deriving a virtual charge
// from AthleteBilling's cadence at all — was removed: BillingCadence is now
// informative-only metadata (the trainer's reference rate) and no longer
// drives any calculation. pagosPorCobrarProvider only reads real pending
// Payment docs.
//
// These tests instead prove the provider NEVER synthesizes a mensual/
// semanal/porSesion charge — not even when a matching billing config exists
// and (for porSesion) the athlete has finished sessions, which used to be
// exactly the data that triggered a virtual charge. `athleteBillingProvider`
// and `sessionsByUidProvider` are still overridden on purpose, to prove
// feeding them "chargeable" data no longer has any effect.

const _trainerId = 'tA';
const _athleteId = 'aA';

TrainerLink _activeLink({bool sharedWithTrainer = true}) => TrainerLink(
      id: 'link-1',
      trainerId: _trainerId,
      athleteId: _athleteId,
      status: TrainerLinkStatus.active,
      requestedAt: DateTime.utc(2026, 1, 1),
      acceptedAt: DateTime.utc(2026, 1, 1),
      sharedWithTrainer: sharedWithTrainer,
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
  List<Payment> payments = const [],
  AthleteBilling? billing,
  List<Session> sessions = const [],
  bool sharedWithTrainer = true,
}) {
  return ProviderContainer(
    overrides: [
      trainerLinksStreamProvider.overrideWith(
        (ref) =>
            Stream.value([_activeLink(sharedWithTrainer: sharedWithTrainer)]),
      ),
      trainerPaymentsProvider.overrideWith(
        (ref) => Stream.value(payments),
      ),
      // pagosPorCobrarProvider no longer reads either of these — overridden
      // purely to prove the tests below are unaffected by them.
      athleteBillingProvider.overrideWith(
        (ref, athleteId) => Stream.value(billing),
      ),
      sessionsByUidProvider.overrideWith((ref, uid) async => sessions),
    ],
  );
}

Future<List<CobroPendiente>?> _readPagos(ProviderContainer container) async {
  await container.read(trainerLinksStreamProvider.future);
  await container.read(trainerPaymentsProvider.future);
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

  group('pagosPorCobrarProvider — no auto-generation (Slice 1)', () {
    test(
      'mensual billing config + no persisted doc for the period → NO virtual '
      'charge is derived (the old code would have created one here)',
      () async {
        final container = _container(billing: mensualBilling);
        addTearDown(container.dispose);

        final results = await _readPagos(container);

        expect(results, isNotNull);
        expect(results, isEmpty);
      },
    );

    test(
      'porSesion billing config + finished sessions, shared history, no real '
      'Payment → 0 computed items (charge is NOT synthesized from session count)',
      () async {
        final container = _container(
          billing: AthleteBilling(
            trainerId: _trainerId,
            athleteId: _athleteId,
            amountArs: 3000,
            cadence: BillingCadence.porSesion,
            updatedAt: now,
          ),
          sessions: [
            _finished(finishedAt: DateTime.utc(2026, 6, 2)),
            _finished(finishedAt: DateTime.utc(2026, 6, 9)),
            _finished(finishedAt: DateTime.utc(2026, 6, 16)),
          ],
        );
        addTearDown(container.dispose);

        final results = await _readPagos(container);

        expect(results, isNotNull);
        expect(results, isEmpty);
      },
    );

    test(
      'a persisted pending doc for the period surfaces as-is (suelto), '
      'regardless of the mensual billing config',
      () async {
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
        expect(results, hasLength(1));
        expect(results!.single.cadence, equals(BillingCadence.suelto));
        expect(results.single.amountArs, equals(8000));
        expect(
            results.single.pendingPaymentIds, equals([existingPendingDoc.id]));
      },
    );

    test(
      'a paid doc for the period does not surface (only pending docs are '
      '"owed")',
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
        expect(results, isEmpty);
      },
    );
  });
}
