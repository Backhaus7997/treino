import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/coach_hub/presentation/sections/pagos/widgets/pagos_buckets_provider.dart';
import 'package:treino/features/payments/application/payment_providers.dart'
    show trainerPaymentsProvider;
import 'package:treino/features/payments/domain/payment.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

final _now = DateTime.now().toUtc();
final _periodStart = DateTime.utc(_now.year, _now.month, 1);

Payment _payment({
  required String id,
  required PaymentStatus status,
  required DateTime createdAt,
  int amountArs = 1000,
}) =>
    Payment(
      id: id,
      trainerId: 'trainer-1',
      athleteId: 'athlete-1',
      amountArs: amountArs,
      concept: 'Test $id',
      status: status,
      createdAt: createdAt,
      paidAt: status == PaymentStatus.paid ? createdAt : null,
    );

ProviderContainer _container(List<Payment> payments) => ProviderContainer(
      overrides: [
        trainerPaymentsProvider.overrideWith(
          (ref) => Stream.value(payments),
        ),
      ],
    );

/// Waits until [pagosBucketsProvider] settles into AsyncData or AsyncError.
///
/// Must listen first to wake up autoDispose providers, then pump the event
/// queue until the stream emits.
Future<AsyncValue<PagosBuckets>> _settled(ProviderContainer c) async {
  final completer = Completer<AsyncValue<PagosBuckets>>();
  final sub = c.listen<AsyncValue<PagosBuckets>>(
    pagosBucketsProvider,
    (_, next) {
      if (!next.isLoading && !completer.isCompleted) {
        completer.complete(next);
      }
    },
    fireImmediately: true,
  );

  // Check immediately (might already be data if stream fired synchronously).
  final current = c.read(pagosBucketsProvider);
  if (!current.isLoading && !completer.isCompleted) {
    completer.complete(current);
  }

  // Give the event loop a few cycles for async stream emission.
  for (var i = 0; i < 30 && !completer.isCompleted; i++) {
    await Future<void>.delayed(Duration.zero);
  }

  sub.close();
  return completer.isCompleted
      ? completer.future
      : c.read(pagosBucketsProvider);
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('pagosBucketsProvider (REQ-PAGW-TAB-001)', () {
    // (a) Empty list → all buckets empty
    test('SCENARIO 3 — empty provider emits all-empty buckets', () async {
      final container = _container([]);
      addTearDown(container.dispose);

      final asyncVal = await _settled(container);

      expect(asyncVal, isA<AsyncData<PagosBuckets>>());
      final buckets = asyncVal.value!;
      expect(buckets.vencidos, isEmpty);
      expect(buckets.porVencer, isEmpty);
      expect(buckets.pagados, isEmpty);
      expect(buckets.todos, isEmpty);
    });

    // (b) Mixed list → correct bucketing
    test(
        'SCENARIO 1 — pending-old → Vencidos, pending-current → PorVencer, '
        'paid → Pagados, all → Todos', () async {
      final old = _payment(
        id: 'old',
        status: PaymentStatus.pending,
        // One day before period start = clearly vencido
        createdAt: _periodStart.subtract(const Duration(days: 1)),
      );
      final current = _payment(
        id: 'current',
        status: PaymentStatus.pending,
        // Exactly period start = porVencer (not vencido)
        createdAt: _periodStart,
      );
      final paid = _payment(
        id: 'paid',
        status: PaymentStatus.paid,
        createdAt: _now,
      );

      final container = _container([old, current, paid]);
      addTearDown(container.dispose);

      final asyncVal = await _settled(container);

      expect(asyncVal, isA<AsyncData<PagosBuckets>>());
      final buckets = asyncVal.value!;

      expect(buckets.vencidos.map((p) => p.id), containsAll(['old']));
      expect(buckets.vencidos.length, 1);

      expect(buckets.porVencer.map((p) => p.id), containsAll(['current']));
      expect(buckets.porVencer.length, 1);

      expect(buckets.pagados.map((p) => p.id), containsAll(['paid']));
      expect(buckets.pagados.length, 1);

      expect(buckets.todos.length, 3);
    });

    // (c) Boundary: createdAt == periodStart → PorVencer, NOT Vencidos
    test('SCENARIO 2 — boundary date (= firstDayOfMonth) lands in PorVencer',
        () async {
      final boundary = _payment(
        id: 'boundary',
        status: PaymentStatus.pending,
        createdAt: _periodStart, // exactly first of month UTC
      );

      final container = _container([boundary]);
      addTearDown(container.dispose);

      final asyncVal = await _settled(container);
      final buckets = asyncVal.value!;

      expect(buckets.vencidos, isEmpty,
          reason: 'period start itself must NOT be Vencido');
      expect(buckets.porVencer.map((p) => p.id), contains('boundary'));
    });

    // (d) Mutual exclusion: no payment in both Vencidos and PorVencer
    test('no payment appears in both Vencidos and PorVencer', () async {
      final old1 = _payment(
        id: 'v1',
        status: PaymentStatus.pending,
        createdAt: _periodStart.subtract(const Duration(days: 5)),
      );
      final cur1 = _payment(
        id: 'p1',
        status: PaymentStatus.pending,
        createdAt: _periodStart.add(const Duration(days: 1)),
      );

      final container = _container([old1, cur1]);
      addTearDown(container.dispose);

      final asyncVal = await _settled(container);
      final buckets = asyncVal.value!;

      final vIds = buckets.vencidos.map((p) => p.id).toSet();
      final pvIds = buckets.porVencer.map((p) => p.id).toSet();

      expect(
        vIds.intersection(pvIds),
        isEmpty,
        reason: 'Vencidos and PorVencer must be disjoint',
      );
    });

    // Edge: many old-pending, none land in porVencer
    test('multiple vencidos all land in Vencidos only', () async {
      final payments = List.generate(
        5,
        (i) => _payment(
          id: 'v$i',
          status: PaymentStatus.pending,
          createdAt: _periodStart.subtract(Duration(days: i + 1)),
        ),
      );

      final container = _container(payments);
      addTearDown(container.dispose);

      final asyncVal = await _settled(container);
      final buckets = asyncVal.value!;

      expect(buckets.vencidos.length, 5);
      expect(buckets.porVencer, isEmpty);
      expect(buckets.todos.length, 5);
    });
  });
}
