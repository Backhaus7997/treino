import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:treino/core/widgets/treino_icon.dart';
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

/// iPhone 14/15 en puntos lógicos — el viewport contra el que está medido el
/// artboard D (stack vertical).
const _kMobileSize = Size(390, 844);

Widget _harness({
  UserProfile? profile,
  Widget home = const Scaffold(body: PricingScreen()),
  double textScale = 1.0,
}) =>
    ProviderScope(
      overrides: [
        userProfileProvider.overrideWith(
          (ref) => Stream<UserProfile?>.value(profile ?? _trainer()),
        ),
      ],
      child: MaterialApp(
        home: home,
        // `builder` envuelve al Navigator, así que `home` hereda este
        // MediaQuery. Es la única forma de forzar el textScaler sin pelearse
        // con el `MediaQuery.fromView` que WidgetsApp inserta siempre.
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
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
      expect(
        find.text(_nombreDeTier(tier)),
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

  // ─────────────────────────────────────────────────────────────────────────
  // Móvil — artboard D
  //
  // TODO ESTE ARCHIVO corría a 1440x900, o sea que la rama angosta de
  // `PricingScreen` (la que ve el PF cuando el CTA "VER PLANES" del paywall lo
  // trae desde la app móvil) NUNCA se había renderizado en un test. Ni una
  // vez. Podía estar rota de punta a punta y la suite seguía verde.
  // ─────────────────────────────────────────────────────────────────────────
  group('móvil 390x844 (artboard D)', () {
    Future<void> pumpMobile(
      WidgetTester tester, {
      UserProfile? profile,
      Widget home = const Scaffold(body: PricingScreen()),
      double textScale = 1.0,
    }) async {
      tester.view.physicalSize = _kMobileSize;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        _harness(profile: profile, home: home, textScale: textScale),
      );
      await tester.pump();
    }

    testWidgets('rendea el stack vertical, no el layout de escritorio',
        (tester) async {
      await pumpMobile(tester);

      // El título en dos líneas y el toggle en mayúsculas son exclusivos del
      // artboard D: si esto aparece, la rama angosta es la que está en
      // pantalla.
      expect(find.text('PLANES Y\nPRECIOS'), findsOneWidget);
      expect(find.text('MENSUAL'), findsOneWidget);
      expect(find.text('ANUAL'), findsOneWidget);
    });

    testWidgets('muestra una tarjeta por CADA tier del enum', (tester) async {
      await pumpMobile(tester);

      for (final tier in SubscriptionTier.values) {
        expect(
          find.text(_nombreDeTier(tier)),
          findsOneWidget,
          reason: 'falta la tarjeta de $tier en el layout móvil',
        );
      }
    });

    testWidgets('Plan 3 muestra su rango y en ningún lado dice "null"',
        (tester) async {
      await pumpMobile(tester);

      expect(find.text('PLAN 3'), findsOneWidget);
      expect(find.text('+15'), findsOneWidget);
      expect(find.text('39.000'), findsOneWidget);

      // `kTierWeightLimits[plan3]` es `null` a propósito. Si alguien interpola
      // el límite en vez de usar la etiqueta de `_tierStudents`, en la tarjeta
      // aparece literalmente "null" y el PF lee una pantalla rota.
      final textos = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .toList();
      expect(
        textos.where((t) => t.toLowerCase().contains('null')),
        isEmpty,
        reason: 'el límite null del plan ilimitado se filtró a la UI: $textos',
      );
    });

    testWidgets('el toggle MENSUAL/ANUAL cambia los precios', (tester) async {
      await pumpMobile(tester);

      expect(find.text('12.000'), findsOneWidget);
      expect(find.text('39.000'), findsOneWidget);
      expect(find.text('POR AÑO'), findsNothing);

      await tester.tap(find.text('ANUAL'));
      await tester.pump();

      expect(find.text('120.000'), findsOneWidget); // Plan 1
      expect(find.text('220.000'), findsOneWidget); // Plan 2
      expect(find.text('390.000'), findsOneWidget); // Plan 3
      expect(find.text('POR AÑO'), findsNWidgets(3));

      await tester.tap(find.text('MENSUAL'));
      await tester.pump();

      expect(find.text('12.000'), findsOneWidget);
      expect(find.text('POR MES'), findsNWidgets(3));
    });

    // El precio-héroe es un `Row` con `mainAxisSize.min` y sin `Flexible`: se
    // pasa del ancho de la tarjeta y tira RenderFlex overflow (rayas amarillas,
    // no un ellipsis). Va envuelto en `FittedBox(scaleDown)` — se achica en vez
    // de recortarse, porque un precio cortado ("39.0…") miente.
    //
    // Un overflow de layout se reporta a `FlutterError.onError` durante el
    // paint y el harness lo convierte en excepción pendiente, así que
    // `takeException()` es el chequeo real.
    for (final scale in <double>[1.0, 1.5]) {
      testWidgets('sin overflow de layout con textScale $scale',
          (tester) async {
        await pumpMobile(tester, textScale: scale);

        expect(
          tester.takeException(),
          isNull,
          reason: 'la pricing page móvil desborda con textScale $scale',
        );

        // El precio anual es el string más largo: si algo se pasa, se pasa acá.
        await tester.tap(find.text('ANUAL'));
        await tester.pump();

        expect(
          tester.takeException(),
          isNull,
          reason: 'los precios anuales desbordan con textScale $scale',
        );
        expect(find.text('390.000'), findsOneWidget);
      });
    }

    // La ruta móvil montaba `Scaffold(body: PricingScreen())` pelado: en un
    // teléfono con notch el título quedaba DEBAJO de la barra de estado.
    testWidgets('el contenido no se mete debajo del notch', (tester) async {
      tester.view.padding = const FakeViewPadding(top: 47);
      addTearDown(tester.view.resetPadding);

      await pumpMobile(tester, home: const PricingRouteScreen());

      expect(
        tester.getTopLeft(find.byType(PricingScreen)).dy,
        greaterThanOrEqualTo(47.0),
        reason: 'la pricing page arranca por encima del inset del notch',
      );
      expect(find.text('PLANES Y\nPRECIOS'), findsOneWidget);
    });

    // Y sin affordance de volver, el único modo de salir era el gesto del
    // sistema — que en Android con navegación por botones ni siquiera está.
    testWidgets('la flecha del header vuelve a la pantalla anterior',
        (tester) async {
      final router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (context, _) => Scaffold(
              body: Center(
                child: Builder(
                  builder: (ctx) => ElevatedButton(
                    onPressed: () => ctx.push('/facturacion/planes'),
                    child: const Text('VER PLANES'),
                  ),
                ),
              ),
            ),
          ),
          GoRoute(
            path: '/facturacion/planes',
            builder: (_, __) => const PricingRouteScreen(),
          ),
        ],
      );
      addTearDown(router.dispose);

      tester.view.physicalSize = _kMobileSize;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            userProfileProvider.overrideWith(
              (ref) => Stream<UserProfile?>.value(_trainer()),
            ),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.tap(find.text('VER PLANES'));
      await tester.pumpAndSettle();

      expect(find.text('PLANES Y\nPRECIOS'), findsOneWidget);

      await tester.tap(find.byIcon(TreinoIcon.back));
      await tester.pumpAndSettle();

      expect(find.text('VER PLANES'), findsOneWidget);
      expect(find.text('PLANES Y\nPRECIOS'), findsNothing);
    });
  });
}

String _nombreDeTier(SubscriptionTier tier) => switch (tier) {
      SubscriptionTier.free => 'FREE',
      SubscriptionTier.plan1 => 'PLAN 1',
      SubscriptionTier.plan2 => 'PLAN 2',
      SubscriptionTier.plan3 => 'PLAN 3',
    };
