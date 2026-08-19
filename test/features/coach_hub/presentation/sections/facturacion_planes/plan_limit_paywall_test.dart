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
  String? billingRoute,
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
                  billingRoute: billingRoute,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
      GoRoute(
        path: '/ajustes',
        builder: (_, __) =>
            const Scaffold(body: Center(child: Text('AJUSTES'))),
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

  testWidgets('desde Plan 2 → upsell a Plan 3 (ilimitado)', (tester) async {
    // Antes Plan 2 era el tope y terminaba en "PLAN A MEDIDA", un callejon sin
    // salida para el PF que MAS paga. Con plan3 ya tiene a donde ir.
    await open(tester, SubscriptionTier.plan2);

    expect(find.text('PASATE A PLAN 3'), findsOneWidget);
    expect(find.text('39.000'), findsOneWidget);
    expect(find.text('PLAN A MEDIDA'), findsNothing);
  });

  testWidgets('desde Plan 3 (tope real) → plan a medida', (tester) async {
    // En la practica es inalcanzable: plan3 no tiene limite, asi que el gate
    // nunca deniega. Queda como red por si el tier cambia.
    await open(tester, SubscriptionTier.plan3);

    expect(find.text('PLAN A MEDIDA'), findsOneWidget);
    expect(find.text('CONTACTANOS'), findsOneWidget);
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

  // ── Cupo ilimitado en el copy ────────────────────────────────────────────
  //
  // REGRESIÓN REAL, publicada en main: `weightLimit` es `null` para plan3, y
  // se interpolaba directo. El upsell al plan MÁS CARO decía «Hasta null
  // alumnos». El test que había verificaba el título («PASATE A PLAN 3») y el
  // precio, pero no el renglón de abajo — pasaba verde con la pantalla rota.
  //
  // Estos tests miran el CUERPO, y hay uno que barre las tres ramas buscando
  // la palabra literal.

  testWidgets('el upsell a Plan 3 no dice «null»', (tester) async {
    await open(tester, SubscriptionTier.plan2);

    expect(find.text('PASATE A PLAN 3'), findsOneWidget);
    expect(find.text('Alumnos sin límite'), findsOneWidget);
    expect(find.textContaining('null'), findsNothing);
  });

  testWidgets('el aviso de suscripción suspendida en Plan 3 no dice «null»',
      (tester) async {
    await tester.pumpWidget(_harness(
      SubscriptionTier.plan3,
      reason: PlanLimitReason.subscriptionInactive,
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.textContaining('sin límite'), findsWidgets);
    expect(find.textContaining('null'), findsNothing);
  });

  testWidgets('NINGUNA rama del paywall dice «null», en ningún tier',
      (tester) async {
    // Barrido: 4 tiers × 2 motivos. Cualquier interpolación nueva de un campo
    // nullable en el copy se cae acá, no en producción.
    for (final tier in SubscriptionTier.values) {
      for (final reason in PlanLimitReason.values) {
        await tester.pumpWidget(_harness(tier, reason: reason));
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();

        expect(
          find.textContaining('null'),
          findsNothing,
          reason: 'el paywall renderiza «null» con tier=$tier reason=$reason',
        );

        await tester.tap(find.text('Ahora no'));
        await tester.pumpAndSettle();
      }
    }
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

  // Regresion: el modal se dispara TAMBIEN desde la app movil, que no tiene
  // pantalla de facturacion. Antes el CTA navegaba a '/ajustes' fijo y ahi
  // moria contra una ruta inexistente: el mensaje era correcto y el boton no
  // hacia nada. Ahora la ruta es explicita y su ausencia se explica.

  testWidgets('REGULARIZAR sin billingRoute avisa en vez de navegar',
      (tester) async {
    await tester.pumpWidget(_harness(
      SubscriptionTier.plan1,
      reason: PlanLimitReason.subscriptionInactive,
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('REGULARIZAR'));
    await tester.pumpAndSettle();

    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.text('AJUSTES'), findsNothing);
  });

  testWidgets('REGULARIZAR con billingRoute navega ahi', (tester) async {
    await tester.pumpWidget(_harness(
      SubscriptionTier.plan1,
      reason: PlanLimitReason.subscriptionInactive,
      billingRoute: '/ajustes',
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('REGULARIZAR'));
    await tester.pumpAndSettle();

    expect(find.text('AJUSTES'), findsOneWidget);
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
