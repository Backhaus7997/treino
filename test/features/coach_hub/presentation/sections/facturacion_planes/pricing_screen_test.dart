import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/coach/domain/subscription_tier.dart';
import 'package:treino/features/coach/domain/trainer_subscription.dart';
import 'package:treino/features/coach_hub/presentation/sections/facturacion_planes/pricing_screen.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';

UserProfile _trainer({SubscriptionTier? tier}) => UserProfile(
      uid: 'pf1',
      email: 'pf@test.com',
      displayName: 'Profe',
      role: UserRole.trainer,
      createdAt: DateTime(2025),
      updatedAt: DateTime(2025),
      subscription: tier == null
          ? null
          : TrainerSubscription(
              tier: tier,
              status: SubscriptionStatus.active,
              weightLimit: tier.weightLimit,
            ),
    );

const _kDesktopSize = Size(1440, 900);

Widget _harness({UserProfile? profile}) => ProviderScope(
      overrides: [
        userProfileProvider.overrideWith(
          (ref) => Stream<UserProfile?>.value(profile ?? _trainer()),
        ),
      ],
      child: const MaterialApp(
        home: Scaffold(body: PricingScreen()),
      ),
    );

void main() {
  // Coach Hub es web/desktop — viewport ancho para el layout de 3 columnas.
  Future<void> pumpDesktop(WidgetTester tester, {UserProfile? profile}) async {
    tester.view.physicalSize = _kDesktopSize;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_harness(profile: profile));
    await tester.pump();
  }

  testWidgets('renderiza los 4 planes con sus alumnos', (tester) async {
    await pumpDesktop(tester);

    expect(find.text('FREE'), findsOneWidget);
    expect(find.text('PLAN 1'), findsOneWidget);
    expect(find.text('PLAN 2'), findsOneWidget);
    // Números de alumnos destacados por card.
    expect(find.text('2'), findsOneWidget);
    expect(find.text('3-7'), findsOneWidget);
    expect(find.text('8-15'), findsOneWidget);
  });

  testWidgets('precios mensuales por default (número sin \$ inline)',
      (tester) async {
    await pumpDesktop(tester);

    expect(find.text('12.000'), findsOneWidget); // Plan 1
    expect(find.text('22.000'), findsOneWidget); // Plan 2
    expect(find.text('0'), findsOneWidget); // Free
    expect(find.text('POR MES'), findsNWidgets(3)); // los 2 pagos
    expect(find.text('SIEMPRE GRATIS'), findsOneWidget); // Free
  });

  testWidgets('toggle Anual cambia a precios anuales', (tester) async {
    await pumpDesktop(tester);

    expect(find.text('POR AÑO'), findsNothing);

    await tester.tap(find.text('Anual'));
    await tester.pump();

    expect(find.text('120.000'), findsOneWidget); // Plan 1 anual
    expect(find.text('220.000'), findsOneWidget); // Plan 2 anual
    expect(find.text('POR AÑO'), findsNWidgets(3));
  });

  testWidgets('Plan 1 marcado como MÁS POPULAR', (tester) async {
    await pumpDesktop(tester);

    expect(find.text('MÁS POPULAR'), findsOneWidget);
  });

  testWidgets('el mensaje de ahorro anual siempre visible', (tester) async {
    await pumpDesktop(tester);

    expect(find.textContaining('Ahorrá 2 meses'), findsOneWidget);
  });

  // El banner "¿MÁS DE 15 ALUMNOS?" se eliminó al agregar el Plan 3.
  // Existía porque no había respuesta arriba de 15; mantenerlo junto al plan
  // ilimitado le diría al PF "próximamente" al lado del plan que ya se lo
  // resuelve.

  // REGRESION: las tarjetas estaban escritas a mano (free, plan1, plan2), asi
  // que agregar `plan3` al enum no lo hacia aparecer en la pricing page — y
  // nada fallaba. El compilador exige exhaustividad en los switch, pero una
  // lista literal no le dice nada. Ahora la grilla itera el enum y este test
  // lo pinea: si agregas un tier y te olvidas de la UI, esto se cae.
  testWidgets('muestra una tarjeta por CADA tier del enum', (tester) async {
    await pumpDesktop(tester);

    for (final tier in SubscriptionTier.values) {
      final nombre = switch (tier) {
        SubscriptionTier.free => 'FREE',
        SubscriptionTier.plan1 => 'PLAN 1',
        SubscriptionTier.plan2 => 'PLAN 2',
        SubscriptionTier.plan3 => 'PLAN 3',
      };
      expect(
        find.text(nombre),
        findsOneWidget,
        reason: 'falta la tarjeta de $tier en la pricing page',
      );
    }
  });

  testWidgets('Plan 3 se muestra como ilimitado y con su precio',
      (tester) async {
    await pumpDesktop(tester);

    expect(find.text('39.000'), findsOneWidget);
    // "+15" y no "∞": sigue la serie de las otras tarjetas y se lee sin
    // interpretar.
    expect(find.text('+15'), findsOneWidget);
    expect(find.text('∞'), findsNothing);
  });

  testWidgets('el tier actual muestra "TU PLAN ACTUAL"', (tester) async {
    await pumpDesktop(tester, profile: _trainer(tier: SubscriptionTier.plan1));

    expect(find.text('TU PLAN ACTUAL'), findsOneWidget);
    // Plan 1 es el actual → no muestra "ELEGIR PLAN" para él. Free tampoco
    // (no se compra), así que quedan Plan 2 y Plan 3.
    expect(find.text('ELEGIR PLAN'), findsNWidgets(2));
  });

  testWidgets('tap en ELEGIR PLAN muestra el aviso mock de MP', (tester) async {
    await pumpDesktop(tester);

    await tester.tap(find.text('ELEGIR PLAN').first);
    await tester.pump();

    expect(
      find.textContaining('Mercado Pago se habilita'),
      findsOneWidget,
    );
  });
}
