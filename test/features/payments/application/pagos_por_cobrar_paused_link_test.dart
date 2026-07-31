import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart'
    show trainerLinksStreamProvider;
import 'package:treino/features/coach/domain/trainer_link.dart';
import 'package:treino/features/coach/domain/trainer_link_status.dart';
import 'package:treino/features/payments/application/pagos_por_cobrar_provider.dart';
import 'package:treino/features/payments/application/payment_providers.dart'
    show trainerPaymentsProvider;
import 'package:treino/features/payments/domain/payment.dart';

// QA H9: pagosPorCobrarProvider iteraba SOLO links 'active', así que un cobro
// pendiente de un alumno con el vínculo 'paused' desaparecía de POR COBRAR y el
// card mostraba "Sin cobros pendientes" mintiendo — el doc Payment seguía
// pending en Firestore. Pausar es un hold temporal, no un corte: la deuda sigue
// siendo deuda. 'terminated' sí queda fuera (el vínculo se cortó).

const _trainerId = 'tA';
const _athleteId = 'aA';

TrainerLink _link(TrainerLinkStatus status) => TrainerLink(
      id: 'link-1',
      trainerId: _trainerId,
      athleteId: _athleteId,
      status: status,
      requestedAt: DateTime.utc(2026, 1, 1),
      acceptedAt: DateTime.utc(2026, 1, 1),
    );

Payment _pendingPayment() => Payment(
      id: 'pay-1',
      trainerId: _trainerId,
      athleteId: _athleteId,
      amountArs: 8000,
      concept: 'Mensualidad',
      status: PaymentStatus.pending,
      createdAt: DateTime.utc(2026, 1, 5),
    );

Future<List<CobroPendiente>?> _read(TrainerLinkStatus status) async {
  final container = ProviderContainer(
    overrides: [
      trainerLinksStreamProvider
          .overrideWith((ref) => Stream.value([_link(status)])),
      trainerPaymentsProvider
          .overrideWith((ref) => Stream.value([_pendingPayment()])),
    ],
  );
  addTearDown(container.dispose);
  await container.read(trainerLinksStreamProvider.future);
  await container.read(trainerPaymentsProvider.future);
  return container.read(pagosPorCobrarProvider).valueOrNull;
}

void main() {
  group('pagosPorCobrarProvider — vínculos pausados/terminados', () {
    test('vínculo PAUSED con cobro pendiente → aparece en POR COBRAR',
        () async {
      final pagos = await _read(TrainerLinkStatus.paused);
      expect(pagos, hasLength(1));
      expect(pagos!.single.athleteId, _athleteId);
      expect(pagos.single.amountArs, 8000);
    });

    test('vínculo ACTIVE con cobro pendiente → aparece (regresión)', () async {
      final pagos = await _read(TrainerLinkStatus.active);
      expect(pagos, hasLength(1));
    });

    test('vínculo TERMINATED → el cobro NO aparece (el vínculo se cortó)',
        () async {
      final pagos = await _read(TrainerLinkStatus.terminated);
      expect(pagos, isEmpty);
    });
  });
}
