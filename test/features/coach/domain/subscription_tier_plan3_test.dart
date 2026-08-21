// Plan 3 — el tier sin límite de alumnos.
//
// `null` en [kTierWeightLimits] significa ILIMITADO, no "falta el dato". La
// diferencia importa: durante la implementación, un `?? FREE_LIMIT` en el
// resolvedor del servidor convertía ese null en 2 — el plan más caro daba
// MENOS alumnos que el más barato, y compilaba perfecto.

import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/coach/domain/subscription_tier.dart';

void main() {
  group('plan3', () {
    test('no tiene límite', () {
      expect(SubscriptionTier.plan3.weightLimit, isNull);
      expect(SubscriptionTier.plan3.isUnlimited, isTrue);
    });

    test('los demás tiers sí tienen límite', () {
      expect(SubscriptionTier.free.weightLimit, 2);
      expect(SubscriptionTier.plan1.weightLimit, 7);
      expect(SubscriptionTier.plan2.weightLimit, 15);
      expect(SubscriptionTier.free.isUnlimited, isFalse);
      expect(SubscriptionTier.plan2.isUnlimited, isFalse);
    });

    test('es el tope de la escalera: no tiene siguiente', () {
      expect(SubscriptionTier.plan2.nextTier, SubscriptionTier.plan3);
      expect(SubscriptionTier.plan3.nextTier, isNull);
    });

    test('precio 39.000 mensual y 390.000 anual', () {
      final precio = kTierPricesArs[SubscriptionTier.plan3]!;
      expect(precio.monthly, 39000);
      // Regla de la escalera: el anual son 10 meses (2 gratis).
      expect(precio.annual, precio.monthly * 10);
    });

    test('serializa y deserializa como plan3', () {
      expect(SubscriptionTierX(SubscriptionTier.plan3).toJson(), 'plan3');
      expect(SubscriptionTierX.fromJson('plan3'), SubscriptionTier.plan3);
    });

    test('un tier desconocido sigue cayendo a free (sin backfill)', () {
      expect(SubscriptionTierX.fromJson('plan99'), SubscriptionTier.free);
      expect(SubscriptionTierX.fromJson(null), SubscriptionTier.free);
    });
  });
}
