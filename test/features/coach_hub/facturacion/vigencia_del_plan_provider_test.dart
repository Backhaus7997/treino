/// vigencia_del_plan_provider_test.dart — `vigenciaDelPlanProvider` recalcula
/// la vigencia SOLA al cruzar un borde, sin que el perfil emita nada.
///
/// Lo que protege:
///
///   1. Que el chip del sidebar y el banner pasen a Free en el instante en que
///      vence la baja, con la pestaña abierta. En ese borde no tiene por qué
///      emitir nadie: el servidor no reescribe el tier y `AppClock` no avisa.
///   2. Que la espera tenga tope, y que sea CORTO. Sin tope, en web, el
///      `setTimeout` de una baja con un mes por delante desborda los 32 bits,
///      dispara en el acto y se reagenda en loop. Y como el provider guarda la
///      vigencia, un timer que llega tarde sólo se corrige en la próxima
///      re-evaluación: con un tope largo, el chip quedaría viejo horas.
///   3. Que el timer muera con el provider. Uno que le sobrevive tumba widget
///      tests ajenos con `!timersPending`.
library;

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/core/utils/app_clock.dart';
import 'package:treino/features/coach/domain/subscription_tier.dart';
import 'package:treino/features/coach/domain/trainer_subscription.dart';
import 'package:treino/features/coach_hub/presentation/sections/facturacion_planes/vigencia_del_plan_provider.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';

/// Un PF en Plan 1 con el período pago hasta [fin]; por default, dado de baja.
UserProfile _pf(
  DateTime fin, {
  SubscriptionStatus status = SubscriptionStatus.cancelled,
}) =>
    UserProfile(
      uid: 'pf1',
      email: 'sofia@treino.app',
      displayName: 'Sofía Ramírez',
      role: UserRole.trainer,
      createdAt: DateTime(2025, 1, 1),
      updatedAt: DateTime(2025, 1, 1),
      subscription: TrainerSubscription(
        tier: SubscriptionTier.plan1,
        status: status,
        weightLimit: SubscriptionTier.plan1.weightLimit,
        currentPeriodEnd: fin,
      ),
    );

ProviderContainer _container(UserProfile perfil) => ProviderContainer(
      overrides: [
        userProfileProvider
            .overrideWith((ref) => Stream<UserProfile?>.value(perfil)),
      ],
    );

void main() {
  tearDown(AppClock.unfreeze);

  group('esperaHasta', () {
    final ahora = DateTime.utc(2026, 10, 1, 15);

    test('si falta menos de un minuto, espera lo que falta', () {
      expect(
        esperaHasta(ahora.add(const Duration(seconds: 20)), ahora: ahora),
        const Duration(seconds: 20),
      );
    });

    test('con horas o un mes por delante espera un minuto', () {
      for (final falta in [
        const Duration(hours: 5),
        const Duration(days: 30)
      ]) {
        expect(
          esperaHasta(ahora.add(falta), ahora: ahora),
          const Duration(minutes: 1),
          reason: 'faltando $falta',
        );
      }
    });

    // Lo que de verdad importa en web: `setTimeout` toma la demora como entero
    // de 32 bits con signo. Los dos ciclos que vende la pricing page, mensual
    // y anual, tienen que entrar.
    test('ninguna espera desborda los 32 bits de setTimeout', () {
      for (final dias in [30, 31, 365]) {
        final espera = esperaHasta(
          ahora.add(Duration(days: dias)),
          ahora: ahora,
        );

        expect(
          espera.inMilliseconds,
          lessThanOrEqualTo(0x7FFFFFFF),
          reason: 'una baja con $dias días por delante',
        );
      }
    });
  });

  // `fakeAsync` corre el timer del provider en tiempo falso. `AppClock` no es
  // un reloj virtual, así que cada salto de hora es un `freeze` explícito.
  //
  // `elapse(Duration.zero)` y no `flushMicrotasks()`: cuando llega el perfil,
  // Riverpod agenda el refresh del provider con un `Timer` de CERO (su vsync
  // por default es un `Future(...)`, `riverpod/src/framework/scheduler.dart`),
  // no con un microtask. Con `flushMicrotasks` ese timer queda pendiente y se
  // cuenta como si fuera el del borde.
  group('vigenciaDelPlanProvider', () {
    final fin = DateTime.utc(2026, 10, 15, 15);

    test('al vencer la baja se recalcula sola y pasa a Free', () {
      fakeAsync((async) {
        AppClock.freeze(fin.subtract(const Duration(hours: 1)).toLocal());
        final container = _container(_pf(fin));
        final vigencia = container.listen(vigenciaDelPlanProvider, (_, __) {});
        async.elapse(Duration.zero);
        expect(vigencia.read().tierEfectivo, SubscriptionTier.plan1);

        // Nadie emite: ni el perfil ni el reloj. Sólo pasa la hora.
        AppClock.freeze(fin.add(const Duration(minutes: 1)).toLocal());
        async.elapse(const Duration(hours: 1));

        expect(vigencia.read().tierEfectivo, SubscriptionTier.free);
        expect(vigencia.read().proximoCambio, isNull);
        container.dispose();
      });
    });

    // El segundo motivo del tope: el provider guarda la vigencia, así que si
    // el reloj salta el borde sin que el timer lo vea, la corrección es la
    // próxima re-evaluación. Con un tope de un día, acá esperaría las cinco
    // horas que faltaban según el reloj viejo.
    test('si el reloj salta el borde, se corrige en a lo sumo un minuto', () {
      fakeAsync((async) {
        AppClock.freeze(fin.subtract(const Duration(hours: 5)).toLocal());
        final container = _container(_pf(fin));
        final vigencia = container.listen(vigenciaDelPlanProvider, (_, __) {});
        async.elapse(Duration.zero);
        expect(vigencia.read().tierEfectivo, SubscriptionTier.plan1);

        // El timer vio pasar un minuto; el reloj de pared, horas.
        AppClock.freeze(fin.add(const Duration(hours: 3)).toLocal());
        async.elapse(const Duration(minutes: 1));

        expect(vigencia.read().tierEfectivo, SubscriptionTier.free);
        container.dispose();
      });
    });

    test('sin baja no agenda nada', () {
      fakeAsync((async) {
        AppClock.freeze(fin.subtract(const Duration(hours: 1)).toLocal());
        final container =
            _container(_pf(fin, status: SubscriptionStatus.active));
        final vigencia = container.listen(vigenciaDelPlanProvider, (_, __) {});
        async.elapse(Duration.zero);

        // Control: el perfil SÍ se leyó (sin él, el tier sería Free).
        expect(vigencia.read().tierEfectivo, SubscriptionTier.plan1);
        expect(async.pendingTimers, isEmpty);
        container.dispose();
      });
    });

    // El footgun de la ventana de gracia: con `keepAlive`, irse el último
    // oyente no descarta el provider, y el timer queda vivo.
    test('cuando se va el último que la mira, el timer se cancela', () {
      fakeAsync((async) {
        AppClock.freeze(fin.subtract(const Duration(hours: 1)).toLocal());
        final container = _container(_pf(fin));
        final vigencia = container.listen(vigenciaDelPlanProvider, (_, __) {});
        async.elapse(Duration.zero);
        expect(vigencia.read().tierEfectivo, SubscriptionTier.plan1);
        expect(async.pendingTimers, hasLength(1));

        vigencia.close();
        async.elapse(Duration.zero);

        expect(async.pendingTimers, isEmpty);
        container.dispose();
      });
    });
  });
}
