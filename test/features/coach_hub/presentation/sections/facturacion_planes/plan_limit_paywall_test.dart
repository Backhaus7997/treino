import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:treino/features/coach/domain/subscription_tier.dart';
import 'package:treino/features/coach_hub/presentation/sections/facturacion_planes/plan_limit_paywall.dart';

/// Monta un botón que abre el paywall para [tier], dentro de un router mínimo
/// (el CTA "VER PLANES" hace context.push).
Widget _harness(
  SubscriptionTier tier, {
  PlanLimitReason reason = PlanLimitReason.planLimit,
  SubscriptionStatus? subscriptionStatus,
}) {
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (context, _) => Scaffold(
          body: Builder(
            builder: (ctx) => Center(
              child: ElevatedButton(
                onPressed: () => showPlanLimitPaywall(
                  ctx,
                  currentTier: tier,
                  reason: reason,
                  subscriptionStatus: subscriptionStatus,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
      GoRoute(
        path: '/facturacion/planes',
        builder: (_, __) =>
            const Scaffold(body: Center(child: Text('PRICING'))),
      ),
    ],
  );
  return MaterialApp.router(routerConfig: router);
}

void main() {
  Future<void> open(WidgetTester tester, SubscriptionTier tier) async {
    await tester.pumpWidget(_harness(tier));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('desde Free → upsell a Plan 1 con su precio', (tester) async {
    await open(tester, SubscriptionTier.free);

    expect(find.text('LLEGASTE AL LÍMITE DE TU PLAN'), findsOneWidget);
    expect(find.text('PASATE A PLAN 1'), findsOneWidget);
    expect(find.text('12.000'), findsOneWidget); // precio Plan 1
    expect(find.text('Hasta 7 alumnos'), findsOneWidget);
    expect(find.text('VER PLANES'), findsOneWidget);
  });

  testWidgets('desde Plan 1 → upsell a Plan 2', (tester) async {
    await open(tester, SubscriptionTier.plan1);

    expect(find.text('PASATE A PLAN 2'), findsOneWidget);
    expect(find.text('22.000'), findsOneWidget); // precio Plan 2
    expect(find.text('Hasta 15 alumnos'), findsOneWidget);
  });

  testWidgets('desde Plan 2 (tope) → plan a medida, sin upsell',
      (tester) async {
    await open(tester, SubscriptionTier.plan2);

    expect(find.text('PLAN A MEDIDA'), findsOneWidget);
    expect(find.text('CONTACTANOS'), findsOneWidget);
    // No hay caja de upsell de otro tier.
    expect(find.textContaining('PASATE A'), findsNothing);
  });

  testWidgets('VER PLANES cierra el modal y navega a la pricing page',
      (tester) async {
    await open(tester, SubscriptionTier.free);

    await tester.tap(find.text('VER PLANES'));
    await tester.pumpAndSettle();

    expect(find.text('PRICING'), findsOneWidget);
  });

  testWidgets('"Ahora no" cierra el modal', (tester) async {
    await open(tester, SubscriptionTier.free);

    await tester.tap(find.text('Ahora no'));
    await tester.pumpAndSettle();

    expect(find.text('LLEGASTE AL LÍMITE DE TU PLAN'), findsNothing);
  });

  // ── Rama subscription-inactive (paywall Fase 7, PR4, diseño D-2) ─────────
  //
  // Son DOS problemas de producto distintos. `plan-limit` = "creciste, comprá
  // más". `subscription-inactive` = "tu derecho está suspendido, regularizá".
  // Un PF con plan2 pago pero suscripción `paused` tiene el límite efectivo de
  // Free: ofrecerle un upsell (o el plan a-medida del tope) es el mensaje
  // equivocado en el peor momento.

  Future<void> openInactive(
    WidgetTester tester,
    SubscriptionTier tier, {
    SubscriptionStatus status = SubscriptionStatus.paused,
  }) async {
    await tester.pumpWidget(_harness(
      tier,
      reason: PlanLimitReason.subscriptionInactive,
      subscriptionStatus: status,
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('subscription-inactive → regularizar, sin upsell ni precio',
      (tester) async {
    await openInactive(tester, SubscriptionTier.plan1);

    expect(find.text('REGULARIZAR'), findsOneWidget);
    // Nada de upsell: no se le vende un plan a quien ya pagó uno.
    expect(find.textContaining('PASATE A'), findsNothing);
    // Sin precio-héroe — el precio no es la pregunta acá.
    expect(find.text('12.000'), findsNothing);
    expect(find.text('22.000'), findsNothing);
    expect(find.text('VER PLANES'), findsNothing);
  });

  testWidgets('subscription-inactive en plan2 NO cae en el plan a medida',
      (tester) async {
    // El tope de tier es irrelevante cuando el problema es el cobro: `reason`
    // manda sobre `currentTier`.
    await openInactive(tester, SubscriptionTier.plan2);

    expect(find.text('REGULARIZAR'), findsOneWidget);
    expect(find.text('PLAN A MEDIDA'), findsNothing);
    expect(find.text('CONTACTANOS'), findsNothing);
  });

  testWidgets('reason por defecto es plan-limit — comportamiento intacto',
      (tester) async {
    // La firma es ADITIVA: los callsites viejos (paywall_preview_screen)
    // siguen compilando y renderizando exactamente igual.
    await open(tester, SubscriptionTier.free);

    expect(find.text('PASATE A PLAN 1'), findsOneWidget);
    expect(find.text('REGULARIZAR'), findsNothing);
  });
}
