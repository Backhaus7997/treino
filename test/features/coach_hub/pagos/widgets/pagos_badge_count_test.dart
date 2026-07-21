import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/coach_hub/presentation/sections/pagos/widgets/pagos_buckets_provider.dart';
import 'package:treino/features/coach_hub/presentation/sections/pagos/widgets/pagos_filtro_provider.dart';
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
}) =>
    Payment(
      id: id,
      trainerId: 'trainer-1',
      athleteId: 'athlete-1',
      amountArs: 1000,
      concept: 'Test $id',
      status: status,
      createdAt: createdAt,
      paidAt: status == PaymentStatus.paid ? createdAt : null,
    );

/// Espera a que [pagosBucketsProvider] deje de estar en loading.
Future<void> _settleBuckets(ProviderContainer c) async {
  final completer = Completer<void>();
  final sub = c.listen<AsyncValue<PagosBuckets>>(
    pagosBucketsProvider,
    (_, next) {
      if (!next.isLoading && !completer.isCompleted) completer.complete();
    },
    fireImmediately: true,
  );

  if (!c.read(pagosBucketsProvider).isLoading && !completer.isCompleted) {
    completer.complete();
  }

  for (var i = 0; i < 30 && !completer.isCompleted; i++) {
    await Future<void>.delayed(Duration.zero);
  }

  sub.close();
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('pagosBadgeCountProvider', () {
    test('null mientras trainerPaymentsProvider está en loading', () {
      final container = ProviderContainer(
        overrides: [
          trainerPaymentsProvider.overrideWith(
            (ref) => Stream.value(<Payment>[]),
          ),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(pagosBadgeCountProvider), isNull);
    });

    test('cuenta solo los pagos vencidos cuando hay data', () async {
      final vencido1 = _payment(
        id: 'v1',
        status: PaymentStatus.pending,
        createdAt: _periodStart.subtract(const Duration(days: 5)),
      );
      final vencido2 = _payment(
        id: 'v2',
        status: PaymentStatus.pending,
        createdAt: _periodStart.subtract(const Duration(days: 1)),
      );
      final porVencer = _payment(
        id: 'pv1',
        status: PaymentStatus.pending,
        createdAt: _periodStart,
      );
      final pagado = _payment(
        id: 'p1',
        status: PaymentStatus.paid,
        createdAt: _now,
      );

      final container = ProviderContainer(
        overrides: [
          trainerPaymentsProvider.overrideWith(
            (ref) => Stream.value([vencido1, vencido2, porVencer, pagado]),
          ),
        ],
      );
      addTearDown(container.dispose);

      await _settleBuckets(container);

      expect(container.read(pagosBadgeCountProvider), 2);
    });

    test('null si el stream de pagos falla', () async {
      final container = ProviderContainer(
        overrides: [
          trainerPaymentsProvider.overrideWith(
            (ref) => Stream.error(Exception('boom')),
          ),
        ],
      );
      addTearDown(container.dispose);

      await _settleBuckets(container);

      expect(container.read(pagosBadgeCountProvider), isNull);
    });
  });

  group('pagosFiltroProvider', () {
    test('default es PagosFiltro.vencidos (la sección abre en triage)', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(pagosFiltroProvider), PagosFiltro.vencidos);
    });
  });
}
