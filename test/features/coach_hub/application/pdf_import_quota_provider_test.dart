import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/coach/domain/subscription_tier.dart';
import 'package:treino/features/coach_hub/application/pdf_import_quota_provider.dart';

void main() {
  final now = DateTime.utc(2026, 10, 22, 15);
  Timestamp at(DateTime d) => Timestamp.fromDate(d);

  group('pdfImportTierFrom (espejo de effectiveTier)', () {
    test('sin suscripción es Free', () {
      expect(pdfImportTierFrom(null, now), SubscriptionTier.free);
    });

    test('active y grace cuentan su tier', () {
      for (final status in ['active', 'grace']) {
        expect(pdfImportTierFrom({'tier': 'plan2', 'status': status}, now),
            SubscriptionTier.plan2);
      }
    });

    test('pending y paused cuentan como Free, igual que el servidor', () {
      for (final status in ['pending', 'paused']) {
        expect(pdfImportTierFrom({'tier': 'plan3', 'status': status}, now),
            SubscriptionTier.free);
      }
    });

    test('baja: su tier mientras corre el período, Free después', () {
      Map<String, Object?> baja(DateTime end) =>
          {'tier': 'plan1', 'status': 'cancelled', 'currentPeriodEnd': at(end)};
      expect(pdfImportTierFrom(baja(now.add(const Duration(days: 1))), now),
          SubscriptionTier.plan1);
      expect(pdfImportTierFrom(baja(now), now), SubscriptionTier.free);
    });

    test('piso prepago vigente: no se sabe (null), no se adivina', () {
      expect(
          pdfImportTierFrom({
            'tier': 'free',
            'status': 'active',
            'prepaidTier': 'plan2',
            'prepaidUntil': at(now.add(const Duration(days: 3))),
          }, now),
          isNull);
    });

    test('piso prepago vencido: vuelve a contar el status', () {
      expect(
          pdfImportTierFrom({
            'tier': 'plan1',
            'status': 'active',
            'prepaidTier': 'plan2',
            'prepaidUntil': at(now.subtract(const Duration(days: 1))),
          }, now),
          SubscriptionTier.plan1);
    });

    test('tier o status desconocidos: null', () {
      expect(pdfImportTierFrom({'tier': 'plan9', 'status': 'active'}, now),
          isNull);
      expect(
          pdfImportTierFrom({'tier': 'plan1', 'status': 'raro'}, now), isNull);
      expect(pdfImportTierFrom('no es un mapa', now), isNull);
    });
  });

  group('pdfImportRemainingFrom', () {
    // Jueves 22/10/2026 en Buenos Aires; la semana empieza el lunes 19.
    final artNow = DateTime.utc(2026, 10, 22, 12);

    test('sin documento: el cupo entero', () {
      final r = pdfImportRemainingFrom(
          usage: null, tier: SubscriptionTier.plan2, artNow: artNow);
      expect(r, (week: 15, day: 10, limitWeekly: 15, limitDaily: 10));
    });

    test('con las claves de hoy descuenta lo usado', () {
      final r = pdfImportRemainingFrom(
        usage: {
          'weekKey': '2026-10-19',
          'weekCount': 5,
          'dayKey': '2026-10-22',
          'dayCount': 2,
        },
        tier: SubscriptionTier.plan1,
        artNow: artNow,
      );
      expect((r.week, r.day), (2, 5));
    });

    test('claves viejas valen cero, como en el servidor', () {
      final r = pdfImportRemainingFrom(
        usage: {
          'weekKey': '2026-10-12',
          'weekCount': 7,
          'dayKey': '2026-10-21',
          'dayCount': 7,
        },
        tier: SubscriptionTier.plan1,
        artNow: artNow,
      );
      expect((r.week, r.day), (7, 7));
    });

    test('nunca negativo', () {
      final r = pdfImportRemainingFrom(
        usage: {
          'weekKey': '2026-10-19',
          'weekCount': 40,
          'dayKey': '2026-10-22',
          'dayCount': 40,
        },
        tier: SubscriptionTier.free,
        artNow: artNow,
      );
      expect((r.week, r.day), (0, 0));
    });
  });
}
