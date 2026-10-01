/// plan_vigencia_test.dart — [VigenciaDelPlan] espeja la rama `cancelled` de
/// `limiteDelStatus` (`functions/src/subscriptions/effective-limit.ts`): el
/// servidor respeta el tier pago mientras `nowMs < currentPeriodEndMs` y, sin
/// fecha o con la fecha cumplida, lo baja a Free.
///
/// Lo que protege, en orden de qué tan caro sale:
///
///   1. Que una baja con el período YA vencido deje de contar como plan actual.
///      Si no, la pricing page marca «TU PLAN ACTUAL» sobre un plan que el PF ya
///      no tiene y no le deja volver a comprarlo.
///   2. Que una baja con días pagos NO se confunda con una vencida. Si no, el PF
///      pierde el botón de volver a suscribirse justo cuando le conviene.
///   3. Que el borde sea el del servidor (estricto). `now == fin` ya es vencido.
///   4. Que nada que no sea una baja cambie de tier por la fecha: un período
///      vencido en un `pending` o `paused` NO lo vuelve Free acá.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:treino/core/utils/app_clock.dart';
import 'package:treino/features/coach/domain/subscription_tier.dart';
import 'package:treino/features/coach/domain/trainer_subscription.dart';
import 'package:treino/features/coach_hub/presentation/sections/facturacion_planes/plan_vigencia.dart';

/// Un instante cualquiera. Los de abajo se miden contra éste.
final _ahora = DateTime.utc(2026, 10, 1, 15);

TrainerSubscription _sub(
  SubscriptionStatus status, {
  SubscriptionTier tier = SubscriptionTier.plan1,
  DateTime? fin,
}) =>
    TrainerSubscription(tier: tier, status: status, currentPeriodEnd: fin);

void main() {
  group('sin baja', () {
    test('sin suscripción es Free, sin baja y sin fecha', () {
      final v = VigenciaDelPlan.de(null, now: _ahora);

      expect(v.tierEfectivo, SubscriptionTier.free);
      expect(v.cancelada, isFalse);
      expect(v.pagadoHasta, isNull);
    });

    // Cualquier estado que no sea `cancelled` conserva el tier del doc, y la
    // fecha NO se mira: un `pending` o `paused` con el período vencido sigue
    // mostrándose con su tier. Este helper no es «el límite efectivo».
    for (final status in SubscriptionStatus.values) {
      if (status == SubscriptionStatus.cancelled) continue;

      test('$status conserva el tier del doc aunque el período esté vencido',
          () {
        final v = VigenciaDelPlan.de(
          _sub(
            status,
            tier: SubscriptionTier.plan2,
            fin: _ahora.subtract(const Duration(days: 30)),
          ),
          now: _ahora,
        );

        expect(v.tierEfectivo, SubscriptionTier.plan2);
        expect(v.cancelada, isFalse);
        expect(v.pagadoHasta, isNull);
      });
    }
  });

  group('baja con días pagos', () {
    test('conserva el tier y dice hasta cuándo', () {
      final fin = _ahora.add(const Duration(days: 14));
      final v = VigenciaDelPlan.de(
        _sub(SubscriptionStatus.cancelled, fin: fin),
        now: _ahora,
      );

      expect(v.tierEfectivo, SubscriptionTier.plan1);
      expect(v.cancelada, isTrue);
      expect(v.pagadoHasta, fin);
    });

    // Un milisegundo antes del fin sigue rigiendo: es `nowMs < currentPeriodEndMs`.
    test('a un milisegundo de vencer todavía rige', () {
      final fin = _ahora.add(const Duration(milliseconds: 1));
      final v = VigenciaDelPlan.de(
        _sub(SubscriptionStatus.cancelled, fin: fin),
        now: _ahora,
      );

      expect(v.tierEfectivo, SubscriptionTier.plan1);
      expect(v.pagadoHasta, fin);
    });
  });

  group('baja con el período vencido', () {
    test('es Free y ya no hay días pagos que re-contratar', () {
      final v = VigenciaDelPlan.de(
        _sub(
          SubscriptionStatus.cancelled,
          fin: _ahora.subtract(const Duration(days: 1)),
        ),
        now: _ahora,
      );

      expect(v.tierEfectivo, SubscriptionTier.free);
      expect(v.cancelada, isTrue, reason: 'la baja se pidió igual');
      expect(v.pagadoHasta, isNull);
    });

    // El borde del servidor es estricto: en el instante exacto del fin ya
    // cayó a Free. Un `<=` acá mostraría un plan que el servidor no respeta.
    test('en el instante exacto del fin ya venció', () {
      final v = VigenciaDelPlan.de(
        _sub(SubscriptionStatus.cancelled, fin: _ahora),
        now: _ahora,
      );

      expect(v.tierEfectivo, SubscriptionTier.free);
      expect(v.pagadoHasta, isNull);
    });

    // El servidor resuelve a Free una baja sin fecha («sin `currentPeriodEnd` no
    // hay período pagado que respetar»).
    test('sin fecha de fin cuenta como vencida', () {
      final v = VigenciaDelPlan.de(
        _sub(SubscriptionStatus.cancelled),
        now: _ahora,
      );

      expect(v.tierEfectivo, SubscriptionTier.free);
      expect(v.cancelada, isTrue);
      expect(v.pagadoHasta, isNull);
    });
  });

  group('el reloj', () {
    // Sin `now`, la hora sale de `AppClock` —el seam que un test congela— y no
    // de un reloj crudo. `freeze` pide un DateTime LOCAL; el fin va en UTC, como
    // lo guarda Firestore, y la comparación es entre instantes.
    test('sin `now` lee AppClock: congelado antes del fin, rige', () {
      AppClock.freeze(DateTime(2026, 10, 1, 12));
      addTearDown(AppClock.unfreeze);

      final v = VigenciaDelPlan.de(
        _sub(SubscriptionStatus.cancelled, fin: DateTime.utc(2026, 10, 15, 15)),
      );

      expect(v.tierEfectivo, SubscriptionTier.plan1);
      expect(v.pagadoHasta, DateTime.utc(2026, 10, 15, 15));
    });

    test('sin `now` lee AppClock: congelado después del fin, venció', () {
      AppClock.freeze(DateTime(2026, 10, 20, 12));
      addTearDown(AppClock.unfreeze);

      final v = VigenciaDelPlan.de(
        _sub(SubscriptionStatus.cancelled, fin: DateTime.utc(2026, 10, 15, 15)),
      );

      expect(v.tierEfectivo, SubscriptionTier.free);
      expect(v.pagadoHasta, isNull);
    });
  });
}
