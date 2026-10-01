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
///      pierde el botón de volver a contratar justo cuando le conviene.
///   3. Que el borde sea el del servidor (estricto). `now == fin` ya es vencido.
///   4. Que nada que no sea una baja cambie de tier por la fecha: un período
///      vencido en un `pending` o `paused` NO lo vuelve Free acá.
///   5. Que [VigenciaDelPlan.primerCobroDiferible] use el MISMO borde que el
///      servidor para diferir el primer cobro (`decidirDiferimiento`, en
///      `functions/src/subscriptions/mp/diferir-primer-cobro.ts`): con menos de
///      un día se cobra en el acto (`finMs - nowMs < MIN_DIFERIMIENTO_MS`), con
///      exactamente un día todavía se difiere. Si el aviso de la pricing page
///      dice «el primer cobro es ese día» donde el servidor cobra ya, miente.
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
      expect(v.primerCobroDiferible, isFalse);
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
        expect(v.primerCobroDiferible, isFalse);
      });

      // El servidor sólo difiere si la suscripción está `cancelled`
      // (`no-esta-cancelada`): un período largo por delante en un estado que no
      // es la baja NO habilita el aviso.
      test('$status con un mes por delante tampoco difiere el primer cobro',
          () {
        final v = VigenciaDelPlan.de(
          _sub(
            status,
            fin: _ahora.add(const Duration(days: 30)),
          ),
          now: _ahora,
        );

        expect(v.primerCobroDiferible, isFalse);
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
      expect(v.primerCobroDiferible, isTrue);
    });

    // Un milisegundo antes del fin sigue rigiendo: es `nowMs < currentPeriodEndMs`.
    // Pero a un milisegundo del fin el servidor ya no difiere: cobra ya.
    test('a un milisegundo de vencer todavía rige, pero no se difiere', () {
      final fin = _ahora.add(const Duration(milliseconds: 1));
      final v = VigenciaDelPlan.de(
        _sub(SubscriptionStatus.cancelled, fin: fin),
        now: _ahora,
      );

      expect(v.tierEfectivo, SubscriptionTier.plan1);
      expect(v.pagadoHasta, fin);
      expect(v.primerCobroDiferible, isFalse);
    });

    // ── El borde de un día: `finMs - nowMs < MIN_DIFERIMIENTO_MS` = no difiere
    group('el primer cobro y el borde de un día', () {
      VigenciaDelPlan conResta(Duration resta) => VigenciaDelPlan.de(
            _sub(SubscriptionStatus.cancelled, fin: _ahora.add(resta)),
            now: _ahora,
          );

      test('con un día y un milisegundo por delante se difiere', () {
        expect(
          conResta(const Duration(days: 1, milliseconds: 1))
              .primerCobroDiferible,
          isTrue,
        );
      });

      // El servidor descarta con `<`, no con `<=`: este es el caso que una
      // comparación `>` en vez de `>=` rompería sin que nada más lo note.
      test('con EXACTAMENTE un día por delante todavía se difiere', () {
        expect(
          conResta(const Duration(days: 1)).primerCobroDiferible,
          isTrue,
        );
      });

      test('con un día menos un milisegundo ya no se difiere', () {
        final v =
            conResta(const Duration(days: 1) - const Duration(milliseconds: 1));

        expect(v.primerCobroDiferible, isFalse);
        // El plan sigue rigiendo y se puede volver a contratar: lo único que
        // cambia es lo que se le promete sobre el primer cobro.
        expect(v.tierEfectivo, SubscriptionTier.plan1);
        expect(v.pagadoHasta, isNotNull);
      });

      test('con una hora por delante no se difiere', () {
        expect(
          conResta(const Duration(hours: 1)).primerCobroDiferible,
          isFalse,
        );
      });
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
      expect(v.primerCobroDiferible, isFalse);
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
      expect(v.primerCobroDiferible, isFalse);
    });
  });

  // `vencida` es lo que la tab de Facturación usa para decidir de dónde sale el
  // tope de alumnos: el servidor no reescribe el doc cuando una baja vence, así
  // que el `weightLimit` cacheado sigue siendo el del plan viejo.
  group('vencida', () {
    test('sin suscripción no está vencida', () {
      expect(VigenciaDelPlan.de(null, now: _ahora).vencida, isFalse);
    });

    // Sólo una BAJA puede vencer. Un `pending` o `paused` con la fecha cumplida
    // no está «vencido» en este sentido: este helper no los baja a Free.
    for (final status in SubscriptionStatus.values) {
      if (status == SubscriptionStatus.cancelled) continue;

      test('$status nunca está vencida, aunque la fecha esté cumplida', () {
        final v = VigenciaDelPlan.de(
          _sub(status, fin: _ahora.subtract(const Duration(days: 30))),
          now: _ahora,
        );

        expect(v.vencida, isFalse);
      });
    }

    test('una baja con días pagos no está vencida', () {
      final v = VigenciaDelPlan.de(
        _sub(
          SubscriptionStatus.cancelled,
          fin: _ahora.add(const Duration(days: 14)),
        ),
        now: _ahora,
      );

      expect(v.vencida, isFalse);
    });

    test('una baja con el período cumplido está vencida', () {
      final v = VigenciaDelPlan.de(
        _sub(
          SubscriptionStatus.cancelled,
          fin: _ahora.subtract(const Duration(days: 1)),
        ),
        now: _ahora,
      );

      expect(v.vencida, isTrue);
      expect(v.tierEfectivo, SubscriptionTier.free);
    });

    test('en el instante exacto del fin ya está vencida', () {
      final v = VigenciaDelPlan.de(
        _sub(SubscriptionStatus.cancelled, fin: _ahora),
        now: _ahora,
      );

      expect(v.vencida, isTrue);
    });

    test('una baja sin fecha de fin está vencida', () {
      final v = VigenciaDelPlan.de(
        _sub(SubscriptionStatus.cancelled),
        now: _ahora,
      );

      expect(v.vencida, isTrue);
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

    // El borde de un día también sale de `AppClock`: es el mismo «ahora» que
    // decide si el período corre, para que las dos respuestas no choquen.
    // El fin va en UTC (como lo guarda Firestore) y se arma sumándole al
    // «ahora» congelado, así que no depende del huso de la máquina.
    test('sin `now` el borde de un día también sale de AppClock', () {
      AppClock.freeze(DateTime(2026, 10, 1, 12));
      addTearDown(AppClock.unfreeze);

      VigenciaDelPlan conResta(Duration resta) => VigenciaDelPlan.de(
            _sub(
              SubscriptionStatus.cancelled,
              fin: AppClock.now().add(resta).toUtc(),
            ),
          );

      expect(conResta(const Duration(hours: 25)).primerCobroDiferible, isTrue);
      expect(conResta(const Duration(hours: 23)).primerCobroDiferible, isFalse);
    });
  });
}
