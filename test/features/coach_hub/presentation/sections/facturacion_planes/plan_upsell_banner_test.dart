// PlanUpsellBanner — la invitación a plan pago que aterriza en Ajustes →
// Cuenta, adonde llevan los dos símbolos de usuario del shell (perfil del
// sidebar y avatar del top bar).
//
// Cubre: que muestre el tier REAL (no un literal como el viejo "Cuenta
// profesional"), que se auto-oculte cuando no hay tier superior que vender, y
// que el CTA llegue a la pricing page. «Real» es el tier efectivo de
// VigenciaDelPlan: una baja con el período vencido es Free aunque el doc siga
// diciendo otro tier.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:treino/core/utils/app_clock.dart';
import 'package:treino/features/coach/domain/subscription_tier.dart';
import 'package:treino/features/coach/domain/trainer_subscription.dart';
import 'package:treino/features/coach_hub/presentation/sections/facturacion_planes/plan_upsell_banner.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';

/// `tier: null` = doc sin `subscription`, que es Free por definición (sin
/// backfill) — el caso más común hoy, no un borde.
///
/// [status] y [fin] (`currentPeriodEnd`) sólo pesan en una baja: es el único
/// estado en que `VigenciaDelPlan` muestra un tier distinto del doc.
UserProfile _pf({
  SubscriptionTier? tier,
  SubscriptionStatus status = SubscriptionStatus.active,
  DateTime? fin,
}) =>
    UserProfile(
      uid: 'pf1',
      email: 'sofia@treino.app',
      displayName: 'Sofía Ramírez',
      role: UserRole.trainer,
      createdAt: DateTime(2025, 1, 1),
      updatedAt: DateTime(2025, 1, 1),
      subscription: tier == null
          ? null
          : TrainerSubscription(
              tier: tier,
              status: status,
              // El tope cacheado es el del tier NOMINAL también en una baja
              // vencida: el servidor no reescribe el doc.
              weightLimit: tier.weightLimit,
              currentPeriodEnd: fin,
            ),
    );

Future<void> _pump(
  WidgetTester tester, {
  SubscriptionTier? tier,
  SubscriptionStatus status = SubscriptionStatus.active,
  DateTime? fin,
}) async {
  final router = GoRouter(
    initialLocation: '/ajustes',
    routes: [
      GoRoute(
        path: '/ajustes',
        builder: (_, __) => const Scaffold(body: PlanUpsellBanner()),
      ),
      GoRoute(
        path: '/facturacion/planes',
        builder: (_, __) => const Text('page:planes'),
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        userProfileProvider.overrideWith(
          (ref) => Stream<UserProfile?>.value(
            _pf(tier: tier, status: status, fin: fin),
          ),
        ),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('PlanUpsellBanner', () {
    testWidgets('sin subscription → invita a salir de Free', (tester) async {
      await _pump(tester);

      expect(find.byKey(const Key('plan_upsell_banner')), findsOneWidget);
      expect(find.text('TU PLAN · FREE'), findsOneWidget);
      expect(
        find.text(
            'Estás en Free, hasta 2 alumnos. Con Plan 1, hasta 7 alumnos.'),
        findsOneWidget,
      );
    });

    testWidgets('en Plan 2 el salto es a ilimitado, no a un número',
        (tester) async {
      await _pump(tester, tier: SubscriptionTier.plan2);

      expect(find.text('TU PLAN · PLAN 2'), findsOneWidget);
      // `weightLimit` null de plan3 es SIN LÍMITE, no una ausencia: si se
      // colapsara con un `?? 0`, el plan más caro se leería como el más chico.
      expect(
        find.text(
          'Estás en Plan 2, hasta 15 alumnos. Con Plan 3, alumnos sin límite.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('en Plan 3 no hay banner — no hay nada que vender',
        (tester) async {
      await _pump(tester, tier: SubscriptionTier.plan3);

      expect(find.byKey(const Key('plan_upsell_banner')), findsNothing);
    });

    testWidgets('VER PLANES abre la pricing page', (tester) async {
      await _pump(tester);

      await tester.tap(find.byKey(const Key('plan_upsell_cta')));
      await tester.pumpAndSettle();

      expect(find.text('page:planes'), findsOneWidget);
    });

    // ── Plan dado de baja ──
    //
    // El servidor le respeta el tier pago a una baja HASTA `currentPeriodEnd`
    // y después la baja a Free sin reescribir el doc (`effective-limit.ts`).
    // En una baja, el banner muestra el tier del doc sólo mientras corran los
    // días pagos; después, Free.
    group('plan dado de baja', () {
      // 1/10/2026 12:00, LOCAL (`AppClock.freeze` lo exige). Los bordes van en
      // UTC, y el más cercano (`vencida`, en UTC+14) queda 7 h antes del
      // reloj: ningún timezone del runner los da vuelta.
      setUp(() => AppClock.freeze(DateTime(2026, 10, 1, 12)));
      tearDown(AppClock.unfreeze);

      final vencida = DateTime.utc(2026, 9, 30, 15);
      final conDiasPagos = DateTime.utc(2026, 10, 15, 15);

      testWidgets('baja vencida de un Plan 1: dice Free y ofrece Plan 1',
          (tester) async {
        await _pump(
          tester,
          tier: SubscriptionTier.plan1,
          status: SubscriptionStatus.cancelled,
          fin: vencida,
        );

        expect(find.text('TU PLAN · FREE'), findsOneWidget);
        // «hasta 2»: el tope del tier que rige, no el del Plan 1 del doc.
        expect(
          find.text(
              'Estás en Free, hasta 2 alumnos. Con Plan 1, hasta 7 alumnos.'),
          findsOneWidget,
        );
        expect(find.text('TU PLAN · PLAN 1'), findsNothing);
      });

      // Control del de arriba: misma baja, mismo reloj, sólo cambia la fecha.
      // Si el Free saliera de `cancelled` a secas y no del vencimiento, esto
      // también diría Free.
      testWidgets('baja con días pagos: el Plan 1 todavía rige',
          (tester) async {
        await _pump(
          tester,
          tier: SubscriptionTier.plan1,
          status: SubscriptionStatus.cancelled,
          fin: conDiasPagos,
        );

        expect(find.text('TU PLAN · PLAN 1'), findsOneWidget);
        expect(
          find.text(
              'Estás en Plan 1, hasta 7 alumnos. Con Plan 2, hasta 15 alumnos.'),
          findsOneWidget,
        );
      });

      // Control del eje del estado: con el plan ACTIVO el servidor ni mira la
      // fecha (`limiteDelStatus` en `effective-limit.ts` devuelve el tope del
      // tier), así que una fecha vencida no lo baja. Por vencimiento sólo cae
      // una baja.
      testWidgets('plan activo con el período vencido sigue en Plan 1',
          (tester) async {
        await _pump(tester, tier: SubscriptionTier.plan1, fin: vencida);

        expect(find.text('TU PLAN · PLAN 1'), findsOneWidget);
      });

      // Un Plan 3 vigente no tiene banner (no hay tier superior que vender).
      // Vencida la baja rige Free, y vuelve a haber algo que ofrecerle.
      testWidgets('baja vencida de un Plan 3: el banner vuelve, en Free',
          (tester) async {
        await _pump(
          tester,
          tier: SubscriptionTier.plan3,
          status: SubscriptionStatus.cancelled,
          fin: vencida,
        );

        expect(find.byKey(const Key('plan_upsell_banner')), findsOneWidget);
        expect(find.text('TU PLAN · FREE'), findsOneWidget);
        expect(
          find.text(
              'Estás en Free, hasta 2 alumnos. Con Plan 1, hasta 7 alumnos.'),
          findsOneWidget,
        );
      });

      // Su control: con días pagos el Plan 3 sigue rigiendo y no hay banner. La
      // ausencia no es vacía: el widget está montado, y sin perfil leído el
      // tier caería a Free y el banner SE VERÍA.
      testWidgets('baja de un Plan 3 con días pagos: sigue sin banner',
          (tester) async {
        await _pump(
          tester,
          tier: SubscriptionTier.plan3,
          status: SubscriptionStatus.cancelled,
          fin: conDiasPagos,
        );

        expect(find.byType(PlanUpsellBanner), findsOneWidget);
        expect(find.byKey(const Key('plan_upsell_banner')), findsNothing);
      });
    });
  });
}
