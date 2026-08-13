import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
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
import 'package:treino/features/payments/data/billing_repository.dart';
import 'package:treino/features/payments/data/payment_repository.dart';
import 'package:treino/features/payments/domain/athlete_billing.dart';
import 'package:treino/features/payments/domain/payment.dart';

// Net-new GAP tests for the payments module. These cover P0/P1 automatable
// cases from docs/test-plan-2026-06-16.md that the existing two test files
// (iso_week_period_key_boundary_test.dart, mi_cuota_provider_boundary_test.dart)
// do NOT touch: the data layer (PaymentRepository / BillingRepository) and the
// trainer-side derivation in pagosPorCobrarProvider (dedup + one-off
// aggregation). Assertions reflect the CORRECT expected behavior, verified
// against the source under lib/features/payments/.

const _trainerId = 'tA';

Payment _pending({
  String id = '',
  String athleteId = 'aA',
  int amountArs = 1500,
  String concept = 'Clase suelta',
  required DateTime createdAt,
}) =>
    Payment(
      id: id,
      trainerId: _trainerId,
      athleteId: athleteId,
      amountArs: amountArs,
      concept: concept,
      status: PaymentStatus.pending,
      createdAt: createdAt,
    );

TrainerLink _activeLink({
  String athleteId = 'aA',
  bool sharedWithTrainer = true,
  DateTime? acceptedAt,
}) =>
    TrainerLink(
      id: 'link-$athleteId',
      trainerId: _trainerId,
      athleteId: athleteId,
      status: TrainerLinkStatus.active,
      requestedAt: DateTime.utc(2026, 1, 1),
      acceptedAt: acceptedAt ?? DateTime.utc(2026, 1, 1),
      sharedWithTrainer: sharedWithTrainer,
    );

/// Container for trainer-side `pagosPorCobrarProvider` tests. Overrides the
/// three upstream dependencies the provider watches (links, all trainer
/// payments, per-athlete billing) so the derivation runs in isolation.
ProviderContainer _trainerContainer({
  required List<TrainerLink> links,
  required List<Payment> payments,
  required Map<String, AthleteBilling?> billingByAthlete,
}) {
  return ProviderContainer(
    overrides: [
      trainerLinksStreamProvider.overrideWith((ref) => Stream.value(links)),
      trainerPaymentsProvider.overrideWith((ref) => Stream.value(payments)),
      athleteBillingProvider.overrideWith(
        (ref, athleteId) => Stream.value(billingByAthlete[athleteId]),
      ),
    ],
  );
}

/// Settles every upstream async dependency the provider reads for [athleteId],
/// then returns the folded data list (or null while still loading).
Future<List<CobroPendiente>?> _readPagos(
  ProviderContainer container,
  String athleteId,
) async {
  await container.read(trainerLinksStreamProvider.future);
  await container.read(trainerPaymentsProvider.future);
  await container.read(athleteBillingProvider(athleteId).future);
  return container.read(pagosPorCobrarProvider).valueOrNull;
}

void main() {
  // ── Data layer: PaymentRepository ─────────────────────────────────────────
  group('PaymentRepository', () {
    late FakeFirebaseFirestore firestore;
    late PaymentRepository repo;

    setUp(() {
      firestore = FakeFirebaseFirestore();
      repo = PaymentRepository(firestore: firestore);
    });

    // payments-04
    test('add writes an auto-id and stamps it into the doc body', () async {
      await repo.add(
        _pending(
          id: '',
          amountArs: 2000,
          concept: 'Clase suelta',
          createdAt: DateTime.utc(2026, 6, 16),
        ),
      );

      final snap = await firestore.collection('payments').get();
      expect(snap.docs, hasLength(1));

      final doc = snap.docs.single;
      // The body 'id' must equal the generated ref id, NOT the empty string
      // that was passed in.
      expect(doc.data()['id'], isNotEmpty);
      expect(doc.data()['id'], equals(doc.id));
      expect(doc.data()['amountArs'], equals(2000));
      expect(doc.data()['concept'], equals('Clase suelta'));
      expect(doc.data()['status'], equals('pending'));
      expect(doc.data()['trainerId'], equals(_trainerId));
    });

    // payments-05
    test(
      'markPaid sets status=paid and paidAt (UTC) without touching other fields',
      () async {
        await repo.add(
          _pending(
            amountArs: 5000,
            concept: 'Mensual',
            createdAt: DateTime.utc(2026, 6, 1),
          ),
        );
        final id =
            (await firestore.collection('payments').get()).docs.single.id;

        // Pass a LOCAL DateTime; the repo must store the UTC-converted instant.
        final localPaidAt = DateTime(2026, 6, 16, 10, 0);
        await repo.markPaid(id, localPaidAt);

        final data =
            (await firestore.collection('payments').doc(id).get()).data()!;
        expect(data['status'], equals('paid'));
        expect(
          data['paidAt'],
          equals(Timestamp.fromDate(localPaidAt.toUtc())),
        );
        // Untouched fields.
        expect(data['amountArs'], equals(5000));
        expect(data['concept'], equals('Mensual'));
        expect(data['trainerId'], equals(_trainerId));
        expect(data['athleteId'], equals('aA'));
      },
    );

    // payments-08
    test('watchForTrainer skips unparseable docs instead of throwing',
        () async {
      // Valid payment.
      await repo.add(
        _pending(
          amountArs: 1000,
          concept: 'Valida',
          createdAt: DateTime.utc(2026, 6, 16),
        ),
      );
      // Malformed doc: amountArs is a String -> fromJson throws -> dropped.
      await firestore.collection('payments').add({
        'trainerId': _trainerId,
        'athleteId': 'aA',
        'amountArs': 'not-a-number',
        'concept': 'Rota',
        'status': 'pending',
        'createdAt': Timestamp.fromDate(DateTime.utc(2026, 6, 16)),
      });

      final list = await repo.watchForTrainer(_trainerId).first;

      expect(list, hasLength(1));
      expect(list.single.concept, equals('Valida'));
      expect(list.single.amountArs, equals(1000));
    });
  });

  // ── Data layer: BillingRepository ─────────────────────────────────────────
  group('BillingRepository', () {
    late FakeFirebaseFirestore firestore;
    late BillingRepository repo;

    setUp(() {
      firestore = FakeFirebaseFirestore();
      repo = BillingRepository(firestore: firestore);
    });

    // payments-10
    test('setConfig merges (does not clobber) an existing config doc',
        () async {
      // Pre-seed the deterministic doc with an unrelated field.
      await firestore.collection('athlete_billing').doc('tA_aA').set({
        'trainerId': _trainerId,
        'athleteId': 'aA',
        'amountArs': 7000,
        'cadence': 'mensual',
        'updatedAt': Timestamp.fromDate(DateTime.utc(2026, 5, 1)),
        'extra': 1,
      });

      await repo.setConfig(
        AthleteBilling(
          trainerId: _trainerId,
          athleteId: 'aA',
          amountArs: 9000,
          cadence: BillingCadence.semanal,
          updatedAt: DateTime.utc(2026, 6, 16),
        ),
      );

      final data =
          (await firestore.collection('athlete_billing').doc('tA_aA').get())
              .data()!;
      expect(data['amountArs'], equals(9000));
      expect(data['cadence'], equals('semanal'));
      // Merge must preserve the unrelated field.
      expect(data['extra'], equals(1));
    });
  });

  // ── Logic layer: pagosPorCobrarProvider ───────────────────────────────────
  group('pagosPorCobrarProvider', () {
    // payments-17 — Slice 1 (2026-07): pagosPorCobrarProvider no longer
    // derives ANY mensual/semanal charge from AthleteBilling (see
    // pagos_por_cobrar_coexistence_test.dart for the full auto-generation
    // regression coverage). A paid Payment for the month is not even read by
    // the mensual/semanal path anymore — this test now just pins that a paid
    // doc never surfaces as "owed" (only pending docs do).
    test(
      'a paid payment for the month does not surface as owed, and no mensual '
      'charge is ever derived from the billing cadence',
      () async {
        final now = DateTime.now().toUtc();
        final monthKey = '${now.year}-${now.month.toString().padLeft(2, '0')}';

        final container = _trainerContainer(
          links: [_activeLink()],
          payments: [
            Payment(
              id: 'paid-1',
              trainerId: _trainerId,
              athleteId: 'aA',
              amountArs: 7000,
              concept: 'Mensual',
              status: PaymentStatus.paid,
              periodKey: monthKey,
              createdAt: now,
              paidAt: now,
            ),
          ],
          billingByAthlete: {
            'aA': AthleteBilling(
              trainerId: _trainerId,
              athleteId: 'aA',
              amountArs: 7000,
              cadence: BillingCadence.mensual,
              updatedAt: now,
            ),
          },
        );
        addTearDown(container.dispose);

        final results = await _readPagos(container, 'aA');

        expect(results, isNotNull);
        // No mensual cadence ever appears — the provider no longer produces it.
        final mensual =
            results!.where((c) => c.cadence == BillingCadence.mensual).toList();
        expect(mensual, isEmpty);
        // And the paid doc itself doesn't surface as an owed charge.
        expect(results, isEmpty);
      },
    );

    // payments-24
    test(
      'multiple one-off pendings aggregate into a single suelto row',
      () async {
        final now = DateTime.now().toUtc();

        final container = _trainerContainer(
          links: [_activeLink()],
          payments: [
            _pending(id: 'p1', amountArs: 1000, concept: 'A', createdAt: now),
            _pending(id: 'p2', amountArs: 2000, concept: 'B', createdAt: now),
            _pending(id: 'p3', amountArs: 500, concept: 'C', createdAt: now),
          ],
          // No recurring config: only the aggregated one-offs should surface.
          billingByAthlete: const {'aA': null},
        );
        addTearDown(container.dispose);

        final results = await _readPagos(container, 'aA');

        expect(results, isNotNull);
        final suelto =
            results!.where((c) => c.cadence == BillingCadence.suelto).toList();
        expect(suelto, hasLength(1));
        expect(suelto.single.amountArs, equals(3500));
        expect(suelto.single.concept, equals('3 cobros pendientes'));
        expect(
          suelto.single.pendingPaymentIds,
          containsAll(<String>['p1', 'p2', 'p3']),
        );
        expect(suelto.single.pendingPaymentIds, hasLength(3));
      },
    );
  });
}
