import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:treino/features/coach/domain/subscription_tier.dart';
import 'package:treino/features/coach_hub/presentation/sections/facturacion_planes/plan_limit_paywall.dart';

/// Monta un botón que abre el paywall para [tier], dentro de un router mínimo
/// (el CTA "VER PLANES" hace context.push).
Widget _harness(SubscriptionTier tier) {
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (context, _) => Scaffold(
          body: Builder(
            builder: (ctx) => Center(
              child: ElevatedButton(
                onPressed: () => showPlanLimitPaywall(ctx, currentTier: tier),
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
}
