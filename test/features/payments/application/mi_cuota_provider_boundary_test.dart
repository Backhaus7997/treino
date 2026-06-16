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

// Regression test for the porSesion HIGH-severity bug in [miCuotaProvider]:
// per-session billing counted every finished session ever, ignoring the
// trainer link's acceptedAt floor, so pre-link workout history was charged.
//
// The sibling ISO-year-boundary bug (weekKey) is proven deterministically at
// the shared-helper level in test/features/payments/
// iso_week_period_key_boundary_test.dart, which this provider now delegates to
// via isoWeekPeriodKey — not duplicated here.

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
  await container.read(
    athleteBillingPairProvider(
      (trainerId: _trainerId, athleteId: _athleteId),
    ).future,
  );
  await container.read(sessionsByUidProvider(_athleteId).future);
  return container.read(miCuotaProvider).valueOrNull;
}

void main() {
  group('miCuotaProvider — porSesion acceptedAt floor', () {
    test(
      'sessions finished BEFORE the link.acceptedAt are not charged',
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
          payments: const [], // never paid yet
          sessions: [
            // 2 pre-link sessions — must be ignored.
            _finished(finishedAt: DateTime.utc(2026, 3, 10)),
            _finished(finishedAt: DateTime.utc(2026, 5, 31)),
            // 3 post-link sessions — must be counted.
            _finished(finishedAt: DateTime.utc(2026, 6, 2)),
            _finished(finishedAt: DateTime.utc(2026, 6, 9)),
            _finished(finishedAt: DateTime.utc(2026, 6, 16)),
          ],
        );
        addTearDown(container.dispose);

        final state = await _readSettled(container);

        expect(state, isNotNull);
        final perSession = state!.items
            .where((i) => i.cadence == BillingCadence.porSesion)
            .toList();
        expect(perSession, hasLength(1));
        // Only the 3 post-acceptedAt sessions: 3 * 3000.
        expect(perSession.single.amountArs, equals(9000));
        expect(perSession.single.concept, equals('3 sesiones'));
      },
    );

    test(
      'with no acceptedAt, the floor falls back to epoch (counts all history)',
      () async {
        final container = _container(
          link: _link(), // acceptedAt == null
          billing: AthleteBilling(
            trainerId: _trainerId,
            athleteId: _athleteId,
            amountArs: 3000,
            cadence: BillingCadence.porSesion,
            updatedAt: DateTime.utc(2026, 1, 1),
          ),
          payments: const [],
          sessions: [
            _finished(finishedAt: DateTime.utc(2026, 3, 10)),
            _finished(finishedAt: DateTime.utc(2026, 6, 2)),
          ],
        );
        addTearDown(container.dispose);

        final state = await _readSettled(container);

        final perSession = state!.items
            .where((i) => i.cadence == BillingCadence.porSesion)
            .single;
        expect(perSession.amountArs, equals(6000));
      },
    );
  });
}
