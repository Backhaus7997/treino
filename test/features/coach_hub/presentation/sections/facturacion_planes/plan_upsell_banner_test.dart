// PlanUpsellBanner — la invitación a plan pago que aterriza en Ajustes →
// Cuenta, adonde llevan los dos símbolos de usuario del shell (perfil del
// sidebar y avatar del top bar).
//
// Cubre: que muestre el tier REAL (no un literal como el viejo "Cuenta
// profesional"), que se auto-oculte cuando no hay tier superior que vender, y
// que el CTA llegue a la pricing page.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:treino/features/coach/domain/subscription_tier.dart';
import 'package:treino/features/coach/domain/trainer_subscription.dart';
import 'package:treino/features/coach_hub/presentation/sections/facturacion_planes/plan_upsell_banner.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';

/// `tier: null` = doc sin `subscription`, que es Free por definición (sin
/// backfill) — el caso más común hoy, no un borde.
UserProfile _pf({SubscriptionTier? tier}) => UserProfile(
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
              status: SubscriptionStatus.active,
              weightLimit: tier.weightLimit,
            ),
    );

Future<void> _pump(WidgetTester tester, {SubscriptionTier? tier}) async {
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
        userProfileProvider
            .overrideWith((ref) => Stream<UserProfile?>.value(_pf(tier: tier))),
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
  });
}
