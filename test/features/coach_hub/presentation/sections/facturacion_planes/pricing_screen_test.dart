import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:treino/core/utils/app_clock.dart';
import 'package:treino/core/widgets/motion/treino_tappable.dart';
import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/features/coach/domain/subscription_tier.dart';
import 'package:treino/features/coach/domain/trainer_subscription.dart';
import 'package:treino/features/coach_hub/presentation/sections/facturacion_planes/plan_checkout.dart';
import 'package:treino/features/coach_hub/presentation/sections/facturacion_planes/pricing_screen.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';

UserProfile _trainer({
  SubscriptionTier? tier,
  SubscriptionStatus status = SubscriptionStatus.active,
  DateTime? currentPeriodEnd,
}) =>
    UserProfile(
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
              status: status,
              weightLimit: tier.weightLimit,
              currentPeriodEnd: currentPeriodEnd,
            ),
    );

const _kDesktopSize = Size(1440, 900);

/// iPhone 14/15 en puntos lógicos — el viewport contra el que está medido el
/// artboard D (stack vertical).
const _kMobileSize = Size(390, 844);

/// Tablet Android en horizontal. Está ARRIBA de `_kNarrowBreakpoint` (820), o
/// sea que entra por el layout ANCHO — pero sigue siendo la app móvil.
///
/// Es el caso que hace que el guard NO pueda ser el breakpoint.
const _kTabletSize = Size(900, 1200);

/// Pone la superficie que SÍ cobra (Coach Hub web) y la devuelve a la
/// plataforma al terminar el test.
///
/// `kIsWeb` es constante de COMPILACIÓN: bajo `flutter test` vale `false`
/// SIEMPRE y no hay forma de moverlo, así que sin este seam ningún test podría
/// RENDERIZAR la pantalla del Coach Hub.
///
/// Pide la superficie con `planCheckoutFor(isWeb: true)` y NO con una constante
/// escrita a mano, y eso importa: la versión anterior fijaba un valor propio,
/// así que se podía romper la rama web de verdad —dejar a TREINO sin poder
/// cobrar en NINGUNA superficie— y los 6522 tests seguían verdes, incluido el
/// que se llama «en web el punto de compra SÍ existe». Medido. Ahora esa
/// mutación se lleva puestos todos los tests de web de este archivo.
///
/// El default —no llamar a esto— deja la superficie REAL de la corrida, que es
/// móvil. Por eso los tests de móvil no lo usan: además de probar la UI,
/// ejercitan [resolvePlanCheckout] de verdad.
void _superficieWeb() {
  debugPlanCheckout = planCheckoutFor(isWeb: true);
  addTearDown(() => debugPlanCheckout = null);
}

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
  //
  // Fija ADEMÁS la superficie web, porque en producción este layout a 1440
  // sólo se ve ahí. La combinación "layout ancho + app móvil" es la tablet, y
  // tiene sus propios tests en el group «guard de superficie» — no se cuela
  // acá por accidente.
  Future<void> pumpDesktop(WidgetTester tester, {UserProfile? profile}) async {
    _superficieWeb();
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

  // docs/limite-ejercicios-pf.md §PR5: sumar `_tierExercises` junto a
  // `_tierStudents`. A diferencia de alumnos, acá el número es el tope EXACTO
  // del tier (20/60/120), no un rango.
  testWidgets('cada tarjeta muestra el tope de ejercicios propios de su plan',
      (tester) async {
    await pumpDesktop(tester);

    expect(find.text('20'), findsOneWidget); // Free
    expect(find.text('60'), findsOneWidget); // Plan 1
    expect(find.text('120'), findsOneWidget); // Plan 2
    // "Sin límite" ahora aparece 4 veces: ejercicios de Plan 3 + plantillas
    // de Plan 1/2/3 (docs/limite-plantillas-pf.md §3 PR5).
    expect(find.text('Sin límite'), findsNWidgets(4));
    expect(find.text('ejercicios propios'), findsNWidgets(4));
  });

  // docs/limite-plantillas-pf.md §3 PR5: sumar `_tierTemplates` junto a
  // `_tierExercises`. Sólo Free tiene tope (3); el resto siempre "Sin límite".
  testWidgets('cada tarjeta muestra el tope de plantillas de su plan',
      (tester) async {
    await pumpDesktop(tester);

    expect(find.text('3'), findsOneWidget); // Free
    expect(find.text('plantillas'), findsNWidgets(4));
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

  testWidgets('en mensual no hay tachado ni chip de descuento — no hay oferta',
      (tester) async {
    await pumpDesktop(tester);

    expect(find.textContaining('%'), findsNothing);
    expect(find.text('\$144.000'), findsNothing);
  });

  testWidgets('en anual cada plan muestra su precio de lista tachado y el %',
      (tester) async {
    await pumpDesktop(tester);
    await tester.tap(find.text('Anual'));
    await tester.pumpAndSettle();

    // 12 meses al precio mensual — contra eso se compara el anual.
    expect(find.text('\$144.000'), findsOneWidget); // Plan 1: 12.000 x 12
    expect(find.text('\$264.000'), findsOneWidget); // Plan 2: 22.000 x 12
    expect(find.text('\$468.000'), findsOneWidget); // Plan 3: 39.000 x 12

    // El % se CALCULA (2 meses gratis sobre 12 = 17%), no está hardcodeado.
    // Free no tiene oferta: son 3 chips, no 4.
    expect(find.text('-17%'), findsNWidgets(3));
  });

  testWidgets(
      'FREE reserva el alto de la fila de oferta: pasar a anual no descalza '
      'la grilla', (tester) async {
    await pumpDesktop(tester);

    // NO se comparan las dos `y` en crudo: PLAN 1 ya arranca 14px más abajo
    // que FREE por la cinta «MÁS POPULAR», y siempre fue así. Lo que tiene
    // que quedar invariante es la DISTANCIA entre los dos precios-héroe: si
    // FREE no reservara el alto de la fila de oferta, al pasar a anual PLAN 1
    // bajaría y FREE no, y la separación crecería.
    double separacion(String free, String plan1) =>
        tester.getTopLeft(find.text(plan1)).dy -
        tester.getTopLeft(find.text(free)).dy;

    final mensual = separacion('0', '12.000');
    await tester.tap(find.text('Anual'));
    await tester.pumpAndSettle();
    final anual = separacion('0', '120.000');

    expect(anual, mensual);
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

  // En WEB el CTA arranca el checkout. Hoy ese checkout es un aviso mock —
  // falta la cuenta de cobro, no una decisión de plataforma— pero el punto de
  // compra existe y está cableado a `PlanCheckoutAvailable.start`.
  testWidgets('en web, tap en ELEGIR PLAN arranca el checkout', (tester) async {
    await pumpDesktop(tester);

    Uri? abierta;
    debugPlanCheckoutCreator =
        ({required tier, required annual}) async => 'https://mp/desktop';
    debugPlanCheckoutLauncher = (u) async {
      abierta = u;
      return true;
    };
    addTearDown(() {
      debugPlanCheckoutCreator = null;
      debugPlanCheckoutLauncher = null;
    });

    await tester.tap(find.text('ELEGIR PLAN').first);
    await tester.pumpAndSettle();

    expect(abierta, Uri.parse('https://mp/desktop'));
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

    // El diseño de referencia ponía la recomendada primero para ganar el fold.
    // Se descartó: en una lista scrolleable romper la escalera de precios
    // obliga a reconstruirla mentalmente, que es justo lo que el PF viene a
    // hacer acá. Este test fija el orden para que no vuelva por descuido.
    testWidgets(
        'las tarjetas van en orden de precio, no la recomendada primero',
        (tester) async {
      await pumpMobile(tester);

      final esperado = SubscriptionTier.values
          .map((t) => switch (t) {
                SubscriptionTier.free => 'FREE',
                SubscriptionTier.plan1 => 'PLAN 1',
                SubscriptionTier.plan2 => 'PLAN 2',
                SubscriptionTier.plan3 => 'PLAN 3',
              })
          .toList();

      // Posición vertical real de cada tarjeta en pantalla.
      final ys = [
        for (final nombre in esperado) tester.getTopLeft(find.text(nombre)).dy,
      ];

      for (var i = 1; i < ys.length; i++) {
        expect(
          ys[i],
          greaterThan(ys[i - 1]),
          reason: '${esperado[i]} deberia ir debajo de ${esperado[i - 1]}',
        );
      }
    });
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

    // Layout angosto: el renglón es UNA sola oración de `ejerciciosTexto`
    // (plan_copy.dart), no el par número/label de la tarjeta ancha.
    testWidgets('cada tarjeta angosta muestra el tope de ejercicios propios',
        (tester) async {
      await pumpMobile(tester);

      expect(find.text('20 ejercicios propios'), findsOneWidget); // Free
      expect(find.text('60 ejercicios propios'), findsOneWidget); // Plan 1
      expect(find.text('120 ejercicios propios'), findsOneWidget); // Plan 2
      expect(
        find.text('ejercicios propios sin límite'),
        findsOneWidget,
      ); // Plan 3
    });

    // Mismo patrón, para plantillas (docs/limite-plantillas-pf.md §3 PR5):
    // el renglón angosto llama a `plantillasTexto` directo.
    testWidgets('cada tarjeta angosta muestra el tope de plantillas',
        (tester) async {
      await pumpMobile(tester);

      expect(find.text('3 plantillas'), findsOneWidget); // Free
      expect(
        find.text('plantillas sin límite'),
        findsNWidgets(3),
      ); // Plan 1, 2 y 3
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

  // ─────────────────────────────────────────────────────────────────────────
  // Guard de superficie — dónde se puede COBRAR
  //
  // TREINO le cobra la suscripción al ENTRENADOR. Guideline 3.1.3(c) exige que
  // toda venta «single user» que ocurra DENTRO de la app pase por in-app
  // purchase, y Play pide lo equivalente: 15-30% de comisión contra el ~2% de
  // una pasarela. Sobre un Plan 2 son $3.300-$6.600 por mes POR ENTRENADOR.
  //
  // Por eso el alta vive sólo en el Coach Hub web. La app móvil informa
  // —planes, precios, cupo— pero no vende y no linkea a comprar afuera.
  // ─────────────────────────────────────────────────────────────────────────
  group('guard de superficie', () {
    Future<void> pump(WidgetTester tester, Size size) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(_harness());
      await tester.pump();
    }

    // EL TEST QUE MÁS VALE.
    //
    // El tipo sellado ya hace que copiar el botón de compra a la rama móvil no
    // compile, pero no cubre el otro movimiento —el fácil, el de un martes a
    // las 6 de la tarde—: tocar `resolvePlanCheckout` para que devuelva la
    // superficie que cobra en todas partes. Eso compila, no rompe ningún tipo,
    // y habilita la compra en iOS y Android de una línea.
    //
    // Este test es lo único que se pone rojo ahí.
    test('sin override, la superficie de la app NO puede cobrar', () {
      // Sin `debugPlanCheckout`: exactamente lo que corre en el teléfono.
      expect(debugPlanCheckout, isNull, reason: 'un test anterior no limpió');

      expect(
        resolvePlanCheckout(),
        isA<PlanCheckoutOnWebOnly>(),
        reason: 'la app móvil quedó habilitada para cobrar dentro de la app: '
            'es 3.1.3(c) en iOS y Play Billing en Android, 15-30% de cada '
            'suscripción del entrenador',
      );
    });

    // El test de arriba corre SIN override, así que sólo puede ver la rama
    // móvil: `kIsWeb` es false bajo `flutter test` y no hay forma de moverlo.
    // La rama web quedaba sin ejecutar por NADIE — se podía cambiarla por
    // «tampoco se cobra en web», o sea dejar a TREINO sin poder vender en
    // ninguna superficie, y los 6522 tests seguían verdes. Medido.
    //
    // `planCheckoutFor` es esa misma decisión con la plataforma afuera, así que
    // acá se pinean LAS DOS ramas y lo único que queda sin cubrir es el token
    // `kIsWeb`.
    test('la superficie se decide por kIsWeb y por nada más', () {
      expect(
        planCheckoutFor(isWeb: false),
        isA<PlanCheckoutOnWebOnly>(),
        reason: 'la app quedó habilitada para cobrar dentro de la app: es '
            '3.1.3(c) en iOS y Play Billing en Android',
      );
      expect(
        planCheckoutFor(isWeb: true),
        isA<PlanCheckoutAvailable>(),
        reason: 'el Coach Hub web dejó de poder cobrar: TREINO no vende en '
            'ninguna superficie',
      );
    });

    // EL CARTEL NO PUEDE SER UN BOTÓN.
    //
    // Los demás tests miran el LABEL y la navegación, y con eso no alcanza: un
    // checkout de verdad colgado del cartel —un `showDialog` con el formulario,
    // un `launchUrl` a la pasarela— no cambia el texto, no navega por GoRouter
    // y no levanta un SnackBar. Verificado: envolviendo esta caja en un
    // `TreinoTappable` con `showDialog`, los otros 4 tests del group se quedan
    // verdes y la app móvil tiene un punto de venta.
    //
    // El tipo sellado tampoco lo ataja: eso no toca `start` ni rompe nada. Esto
    // sí.
    for (final caso in <(String, Size)>[
      ('angosto', _kMobileSize),
      ('ancho', _kTabletSize),
    ]) {
      testWidgets(
          'en móvil NADA que hable de contratar es tappable '
          '(layout ${caso.$1})', (tester) async {
        await pump(tester, caso.$2);

        // Los DOS textos, y esto no es exhaustividad por gusto. La versión
        // anterior miraba sólo el corto —el del slot del CTA— y dejaba afuera
        // el cartel largo del pie. Una auditoría colgó un `TreinoTappable` con
        // `showDialog('CHECKOUT MERCADO PAGO')` justo de ese pie: la app móvil
        // quedó vendiendo y la suite ENTERA siguió verde (6527, 0 issues).
        //
        // La regla que sale de ahí: todo texto que le diga al PF dónde se
        // contrata es un candidato a que alguien lo vuelva el atajo, así que
        // todos entran acá. Si mañana aparece un tercero, va en esta lista.
        // ⚠️ ESTE TEST CAMBIÓ DE TRABAJO EL 2026-09-15, y el de antes se
        // quedaría verde sobre el problema.
        //
        // Antes verificaba que los dos carteles EXISTIERAN y no fueran
        // tappables. Ahora los carteles **no existen**: `pricing_screen.dart`
        // los vació bajo 3.1.3(f), que ampara este binario sólo «provided
        // there is no purchasing inside the app, **or calls to action for
        // purchase outside of the app**». Un cartel que dice dónde se paga ya
        // es un call to action, tappable o no.
        //
        // Así que la garantía es más fuerte: no hay nada que envolver.
        //
        // Se sigue barriendo por SUBSTRING y no por texto exacto: si alguien
        // vuelve a escribir «TREINO web» con otro copy, cae acá igual. Y el
        // que impide que reaparezca en el FUENTE es
        // `test/features/paywall/anti_steering_movil_test.dart`.
        for (final aguja in <String>[
          'TREINO WEB',
          'TREINO web',
          'se contrata'
        ]) {
          expect(
            find.textContaining(aguja),
            findsNothing,
            reason: 'volvió a aparecer «$aguja» en la pricing page móvil. '
                'Bajo 3.1.3(f) eso es un call to action de compra externa, y '
                'el amparo se cae solo el día que el alumno compre por IAP.\n'
                'Si hace falta avisarle al PF dónde pagar: por MAIL, que Apple '
                'permite explícitamente. Adentro de la app, no.',
          );
        }

        // El guard de tappabilidad se conserva sobre lo que SÍ queda en
        // pantalla. Una auditoría colgó una vez un `TreinoTappable` con
        // `showDialog('CHECKOUT MERCADO PAGO')` del pie, la app móvil quedó
        // vendiendo, y la suite entera siguió verde (6527, 0 issues).
        for (final tipo in <Type>[TreinoTappable, GestureDetector, InkWell]) {
          expect(
            find.ancestor(
              of: find.textContaining('plan'),
              matching: find.byType(tipo),
            ),
            findsNothing,
            reason: 'algo que habla de planes quedó tappable vía $tipo en la '
                'app móvil: sea lo que sea que abra, es un punto de compra '
                'adentro de la app',
          );
        }
      });
    }

    testWidgets('en móvil se ven los planes y NO se ofrece comprar',
        (tester) async {
      await pump(tester, _kMobileSize);

      // Ve todo: los cuatro planes, los precios y su cupo. Que no pueda pagar
      // acá no significa que le falte información.
      for (final tier in SubscriptionTier.values) {
        expect(find.text(_nombreDeTier(tier)), findsOneWidget);
      }
      expect(find.text('12.000'), findsOneWidget);
      expect(find.text('22.000'), findsOneWidget);
      expect(find.text('39.000'), findsOneWidget);
      expect(find.text('+15'), findsOneWidget);

      // Lo único que no hay es el punto de compra.
      expect(find.text('ELEGIR PLAN'), findsNothing);

      // Y en su lugar, NADA. Este bloque decía lo contrario —«el PF tiene que
      // saber dónde se da de alta»— y esa decisión se dio vuelta el
      // 2026-09-15: bajo 3.1.3(f) decirlo es un call to action de compra
      // externa. Sigue sin «próximamente» y sin nombrar a Apple.
      //
      // ⚠️ Lo que esto cuesta está escrito en `pricing_screen.dart`, no acá:
      // el PF que entró por el teléfono queda sin saber dónde pagar, y la
      // salida es un mail.
      expect(find.text('SE CONTRATA EN TREINO WEB'), findsNothing);
      expect(
        find.textContaining('TREINO web'),
        findsNothing,
        reason: 'la app móvil no puede nombrar dónde se da de alta',
      );
      final textos = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => (t.data ?? '').toLowerCase());
      for (final prohibida in ['próximamente', 'proximamente', 'apple']) {
        expect(
          textos.where((t) => t.contains(prohibida)),
          isEmpty,
          reason: 'la pricing page móvil dice "$prohibida"',
        );
      }
    });

    // Hasta el 2026-09-29 el slot del CTA en móvil dibujaba una pill vacía
    // (borde + sin texto, `_kSubscribeElsewhereShort == ''`): ruido visual
    // que no decía nada. Ahora esas tarjetas no dibujan NADA ahí — sin caja,
    // sin espacio reservado. `TU PLAN ACTUAL` y `GRATIS` (Free, la tarjeta
    // actual por default) se quedan.
    testWidgets(
        'en móvil, una tarjeta de plan no actual no tiene CTA (sin caja)',
        (tester) async {
      await pump(tester, _kMobileSize);

      // Free es el tier actual por default de `_trainer()`: su pill sigue
      // ahí ("GRATIS"), con tamaño real.
      final free = tester.getSize(find.byKey(const ValueKey('plan_cta_free')));
      expect(free.height, greaterThan(0),
          reason: 'la tarjeta actual (Free) perdió su pill "GRATIS"');

      // Plan 1 / 2 / 3: no son el actual y cobran — antes dibujaban la pill
      // vacía, ahora no dibujan nada.
      for (final tier in [
        SubscriptionTier.plan1,
        SubscriptionTier.plan2,
        SubscriptionTier.plan3,
      ]) {
        final size =
            tester.getSize(find.byKey(ValueKey('plan_cta_${tier.name}')));
        expect(
          size,
          Size.zero,
          reason: '$tier todavía reserva espacio para un CTA en móvil',
        );
      }
    });

    // El caso que hace que el guard NO pueda ser el breakpoint: una tablet
    // Android a 900pt entra por el layout ANCHO y sigue siendo la app.
    //
    // Si alguien resolviera la compra por `constraints.maxWidth` en vez de por
    // superficie, TODOS los demás tests de este group seguirían verdes y esto
    // se pondría rojo solo.
    testWidgets('el layout ANCHO en móvil tampoco vende', (tester) async {
      await pump(tester, _kTabletSize);

      // Confirmá que estamos en la rama ancha y no en la angosta: el título en
      // una sola línea es exclusivo de `_WideBody`.
      expect(find.text('PLANES Y PRECIOS'), findsOneWidget);
      expect(find.text('PLANES Y\nPRECIOS'), findsNothing);

      expect(find.text('ELEGIR PLAN'), findsNothing);
      // Ni el punto de compra ni el cartel que decía dónde comprar: ver el
      // bloque equivalente del layout angosto.
      expect(find.text('SE CONTRATA EN TREINO WEB'), findsNothing);
      expect(find.textContaining('TREINO web'), findsNothing);
    });

    // No alcanza con que el label diga otra cosa: lo que la guideline mira es
    // si desde la app se puede llegar a pagar. Así que se disparan los
    // callbacks de todos los [TreinoTappable] de la pantalla —incluidos los que
    // quedaron fuera del fold, que un `tester.tap` no alcanzaría, y ahí están
    // justo PLAN 2 y PLAN 3— y se exige que ninguno navegue ni abra un aviso.
    //
    // Alcance REAL, para no confiarse de más: esto ve `TreinoTappable`,
    // navegación por GoRouter a rutas de un segmento, SnackBars y —desde que
    // una auditoría se coló por ahí— CUALQUIER ruta modal, que es como se
    // manifiestan `showDialog` y `showModalBottomSheet`. Se cuentan los
    // `ModalBarrier` antes y después en vez de buscar un tipo de diálogo
    // concreto, porque un diálogo propio del repo no sería `AlertDialog` ni
    // `Dialog` y se escaparía igual.
    //
    // Lo que sigue SIN ver: un `launchUrl` y un `GestureDetector` pelado. Los
    // cubren sus propios tests («NADA que hable de contratar es tappable» y «la
    // carpeta del paywall no abre nada afuera»); los tres juntos son el guard,
    // no éste solo.
    testWidgets('en móvil ningún tap lleva a comprar', (tester) async {
      final visitadas = <String>[];
      final router = GoRouter(
        initialLocation: '/facturacion/planes',
        routes: [
          GoRoute(
            path: '/facturacion/planes',
            builder: (_, __) => const PricingRouteScreen(),
          ),
          // Cualquier destino al que alguien cablee una compra cae acá.
          GoRoute(
            path: '/:cualquiera',
            builder: (_, state) {
              visitadas.add(state.uri.toString());
              return const Scaffold(body: Text('OTRA PANTALLA'));
            },
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
      await tester.pumpAndSettle();

      // La flecha de VOLVER queda AFUERA del barrido. No es una venta —lleva
      // a `/coach`, de donde vino el PF— y entró acá recién cuando pasó a ser
      // un `TreinoIconButton` del kit: como `IconButton` de Material no era
      // `TreinoTappable` y el barrido no la veía. Dispararla desmonta la
      // página y el resto del guard se queda sin nada que mirar.
      final volver = tester
          .widgetList<TreinoTappable>(find.descendant(
            of: find.byKey(const Key('pricing_back_button')),
            matching: find.byType(TreinoTappable),
          ))
          .map((w) => w.onTap)
          .toSet();

      final taps = tester
          .widgetList<TreinoTappable>(find.byType(TreinoTappable))
          .map((w) => w.onTap)
          .whereType<VoidCallback>()
          .where((t) => !volver.contains(t))
          .toList();

      // Línea de base ANTES de tocar nada: el router ya puede tener barreras
      // propias, así que lo que importa es el DELTA, no el valor absoluto.
      final modalesAntes = tester.widgetList(find.byType(ModalBarrier)).length;

      for (final tap in taps) {
        tap();
        await tester.pumpAndSettle();
      }

      expect(
        tester.widgetList(find.byType(ModalBarrier)).length,
        modalesAntes,
        reason: 'un tap abrió una ruta modal (showDialog / bottom sheet). Si '
            'es un checkout, es una venta adentro de la app',
      );

      expect(
        visitadas,
        isEmpty,
        reason: 'un tap de la pricing page móvil navegó a $visitadas',
      );
      expect(
        find.byType(SnackBar),
        findsNothing,
        reason: 'un tap abrió un aviso; si es de cobro, es una venta in-app',
      );
      // Seguimos en la pricing page, informando.
      expect(find.text('PLANES Y\nPRECIOS'), findsOneWidget);
      expect(find.text('OTRA PANTALLA'), findsNothing);
    });

    testWidgets('en web el punto de compra SÍ existe', (tester) async {
      _superficieWeb();
      await pump(tester, _kMobileSize);

      // Misma pantalla, mismo ancho de teléfono: lo único que cambió es la
      // superficie. Prueba que el guard no es el breakpoint disfrazado.
      expect(find.text('ELEGIR PLAN'), findsNWidgets(3));
      expect(find.text('SE CONTRATA EN TREINO WEB'), findsNothing);
      expect(find.textContaining('desde TREINO web'), findsNothing);

      // El punto de compra AHORA cobra de verdad: pide el checkout al servidor
      // y navega. Los dos seams cortan antes de la red y antes del navegador —
      // sin ellos este test abriría Mercado Pago desde la suite.
      SubscriptionTier? pedido;
      bool? pidioAnual;
      Uri? abierta;
      debugPlanCheckoutCreator = ({required tier, required annual}) async {
        pedido = tier;
        pidioAnual = annual;
        return 'https://mp/checkout';
      };
      debugPlanCheckoutLauncher = (u) async {
        abierta = u;
        return true;
      };
      addTearDown(() {
        debugPlanCheckoutCreator = null;
        debugPlanCheckoutLauncher = null;
      });

      await tester.tap(find.text('ELEGIR PLAN').first);
      await tester.pumpAndSettle();

      // Que el tap PIDA el checkout y NAVEGUE. Antes bastaba con un cartel;
      // ahora el test tiene que ver las dos mitades, porque cualquiera de las
      // dos rota deja al PF sin poder pagar y la pantalla igual de linda.
      expect(pedido, isNotNull);
      expect(pidioAnual, isNotNull);
      expect(abierta, Uri.parse('https://mp/checkout'));
    });

    testWidgets('si el servidor no devuelve checkout, avisa y NO navega',
        (tester) async {
      _superficieWeb();
      await pump(tester, _kMobileSize);

      var navego = false;
      debugPlanCheckoutCreator =
          ({required tier, required annual}) async => null;
      debugPlanCheckoutLauncher = (u) async {
        navego = true;
        return true;
      };
      addTearDown(() {
        debugPlanCheckoutCreator = null;
        debugPlanCheckoutLauncher = null;
      });

      await tester.tap(find.text('ELEGIR PLAN').first);
      await tester.pumpAndSettle();

      expect(navego, isFalse);
      expect(find.textContaining('No pudimos'), findsOneWidget);
    });

    testWidgets('si la llamada explota, avisa y NO navega', (tester) async {
      // El PF tiene que enterarse de que no pasó nada. Tragarse el error deja
      // un botón que no hace absolutamente nada al tocarlo.
      _superficieWeb();
      await pump(tester, _kMobileSize);

      var navego = false;
      debugPlanCheckoutCreator =
          ({required tier, required annual}) async => throw Exception('boom');
      debugPlanCheckoutLauncher = (u) async {
        navego = true;
        return true;
      };
      addTearDown(() {
        debugPlanCheckoutCreator = null;
        debugPlanCheckoutLauncher = null;
      });

      await tester.tap(find.text('ELEGIR PLAN').first);
      await tester.pumpAndSettle();

      expect(navego, isFalse);
      expect(find.textContaining('No pudimos'), findsOneWidget);
    });

    // La salida que NINGÚN test de widgets ve.
    //
    // `url_launcher` ya es dependencia (`pubspec.yaml`) y
    // `LaunchMode.inAppBrowserView` ya es patrón del repo
    // (`exercise_video_player.dart` lo usa para YouTube, con su dartdoc sobre
    // Chrome Custom Tab / SFSafariViewController). O sea: abrir el checkout de
    // Mercado Pago en un WebView —que para Apple sigue siendo ADENTRO de la
    // app— está a un copy-paste de dos carpetas.
    //
    // Un `launchUrl` no navega por GoRouter, no levanta un SnackBar y no
    // cambia ningún label, así que los tests de arriba no lo verían. Éste sí, y
    // es el único que cubre TODA la carpeta y no sólo esta pantalla.
    //
    // Si alguna vez hace falta abrir algo de verdad acá (los términos, por
    // ejemplo), este test se cae y esa es la idea: que la conversación pase por
    // alguien antes que por el compilador.
    test('la carpeta del paywall no abre nada afuera de la app', () {
      final dir = Directory(
        'lib/features/coach_hub/presentation/sections/facturacion_planes',
      );
      expect(
        dir.existsSync(),
        isTrue,
        reason: 'no encontré la carpeta del paywall desde ${Directory.current}'
            ' — si se movió, movete este test con ella en vez de borrarlo',
      );

      // ── Prohibido SIEMPRE, `plan_checkout.dart` incluido ──
      //
      // Todo esto abre el checkout ADENTRO de la app, y para 3.1.3(c) eso es
      // una venta in-app: exactamente lo que el tipo sellado existe para
      // evitar, y por un camino que el sellado NO ve. Que el archivo del
      // punto de compra pueda navegar afuera no lo habilita a traerse el
      // checkout adentro.
      const prohibidosSiempre = <String>[
        'WebViewController',
        'WebViewWidget',
        'InAppBrowser',
        'LaunchMode.inAppBrowserView',
        'LaunchMode.inAppWebView',
      ];

      // ── Prohibido en toda la carpeta MENOS en el punto de compra ──
      //
      // `plan_checkout.dart` navega al `init_point` de Mercado Pago, y eso es
      // legítimo: es el ÚNICO archivo del que `PlanCheckoutAvailable.start`
      // puede salir, y saca al usuario de la app en vez de traer el pago
      // adentro. En cualquier OTRO archivo de la carpeta sigue siendo el
      // agujero de siempre — un camino de cobro al lado del cartel, en la
      // rama móvil, que el sellado no atrapa.
      const prohibidosSalvoEnElPuntoDeCompra = <String>[
        'package:url_launcher',
        'launchUrl(',
        'launchUrlString(',
      ];
      const puntoDeCompra = 'plan_checkout.dart';
      final hallazgos = <String>[];
      // `recursive: true` a propósito: sin eso, un `launchUrl` metido en
      // `facturacion_planes/<subcarpeta>/` era invisible para este test — que
      // es justo donde va a terminar el código el día que la carpeta crezca.
      for (final f in dir.listSync(recursive: true).whereType<File>()) {
        if (!f.path.endsWith('.dart')) continue;
        // Sin los comentarios: el archivo de al lado EXPLICA por qué no puede
        // haber un launcher acá, y nombrarlo en un dartdoc no es cablearlo. La
        // primera versión de este test se cayó contra su propia explicación.
        final codigo = f.readAsLinesSync().map((l) {
          final i = l.indexOf('//');
          return i == -1 ? l : l.substring(0, i);
        }).join('\n');
        for (final aguja in prohibidosSiempre) {
          if (codigo.contains(aguja)) hallazgos.add('${f.path}: $aguja');
        }
        if (!f.path.endsWith(puntoDeCompra)) {
          for (final aguja in prohibidosSalvoEnElPuntoDeCompra) {
            if (codigo.contains(aguja)) hallazgos.add('${f.path}: $aguja');
          }
        }
      }

      expect(
        hallazgos,
        isEmpty,
        reason: 'apareció una forma de abrir algo afuera en la carpeta del '
            'paywall: $hallazgos. Un checkout en un WebView o en el navegador '
            'lanzado DESDE la app sigue siendo una venta in-app para 3.1.3(c), '
            'y el guard de superficie no lo ve',
      );
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // Plan dado de baja — «reactivar plan» y qué cuenta como plan actual
  //
  // Una suscripción `cancelled` conserva su tier pago HASTA `currentPeriodEnd`
  // y después es Free (el servidor: `nowMs < currentPeriodEndMs`). La pantalla
  // leía el tier del doc a secas, y eso fallaba en las dos puntas:
  //
  //   - con días pagos, el plan decía «TU PLAN ACTUAL» y no se podía volver a
  //     contratar: el actual no se vende;
  //   - ya vencida, seguía diciendo «TU PLAN ACTUAL» sobre un plan que el PF no
  //     tiene, y tampoco se podía comprar.
  //
  // Lo que se vende y lo que se dice cambia por SUPERFICIE: sólo el Coach Hub
  // web ofrece «REACTIVAR PLAN» y la fecha. La app móvil no gana ni una
  // palabra (3.1.3(f)): sólo cambia QUÉ tarjeta lleva «TU PLAN ACTUAL».
  //
  // El reloj va congelado en `AppClock`: 1/10/2026 12:00. Los fines de período
  // van en UTC, como los guarda Firestore.
  // ─────────────────────────────────────────────────────────────────────────
  group('plan dado de baja', () {
    setUp(() => AppClock.freeze(DateTime(2026, 10, 1, 12)));
    tearDown(AppClock.unfreeze);

    // 15:00 UTC = 12:00 ART → «15/10».
    final conDiasPagos = DateTime.utc(2026, 10, 15, 15);
    final vencido = DateTime.utc(2026, 9, 30, 15);

    UserProfile cancelado(
      DateTime? fin, {
      SubscriptionTier tier = SubscriptionTier.plan1,
    }) =>
        _trainer(
          tier: tier,
          status: SubscriptionStatus.cancelled,
          currentPeriodEnd: fin,
        );

    Future<void> pumpEn(
      WidgetTester tester,
      Size size,
      UserProfile profile, {
      required bool web,
      double textScale = 1.0,
    }) async {
      if (web) _superficieWeb();
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(_harness(profile: profile, textScale: textScale));
      await tester.pump();
    }

    /// [matching] DENTRO del pie de la tarjeta de [tier] (`plan_cta_<tier>`).
    Finder enElPieDe(SubscriptionTier tier, Finder matching) => find.descendant(
          of: find.byKey(ValueKey('plan_cta_${tier.name}')),
          matching: matching,
        );

    /// Todo lo que la pantalla dice y todo lo que se puede tocar, en un árbol
    /// NUEVO: con el `ProviderScope` anterior el stream del perfil no se
    /// reemplaza y se compararía una pantalla consigo misma.
    Future<({List<String> textos, int tappables})> fotoDe(
      WidgetTester tester,
      Size size,
      UserProfile profile, {
      required bool web,
    }) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await pumpEn(tester, size, profile, web: web);
      return (
        textos: tester
            .widgetList<Text>(find.byType(Text))
            .map((t) => t.data ?? '')
            .toList(),
        tappables: tester.widgetList(find.byType(TreinoTappable)).length,
      );
    }

    // ── Coach Hub web: es donde se puede cobrar ──────────────────────────────
    for (final (layout, size, etiquetaAnual) in <(String, Size, String)>[
      ('ancho', _kDesktopSize, 'Anual'),
      ('angosto', _kMobileSize, 'ANUAL'),
    ]) {
      group('web, layout $layout', () {
        testWidgets(
            'con días pagos el plan ofrece REACTIVAR PLAN, no TU PLAN '
            'ACTUAL', (tester) async {
          await pumpEn(tester, size, cancelado(conDiasPagos), web: true);

          expect(
            enElPieDe(SubscriptionTier.plan1, find.text('REACTIVAR PLAN')),
            findsOneWidget,
          );
          expect(
            enElPieDe(SubscriptionTier.plan1, find.text('TU PLAN ACTUAL')),
            findsNothing,
          );
          // Ninguna otra tarjeta es la actual: Free tampoco, porque el plan
          // pago sigue rigiendo. Los otros dos planes se venden como siempre.
          expect(find.text('TU PLAN ACTUAL'), findsNothing);
          expect(find.text('ELEGIR PLAN'), findsNWidgets(2));
          expect(find.text('REACTIVAR PLAN'), findsOneWidget);
        });

        // El botón es el MISMO punto de compra que «ELEGIR PLAN»: pide el
        // checkout de ESTE tier con el ciclo que el toggle tenga puesto.
        testWidgets(
            'tocarlo arranca el checkout del mismo plan con el ciclo del '
            'toggle', (tester) async {
          await pumpEn(tester, size, cancelado(conDiasPagos), web: true);

          final pedidos = <(SubscriptionTier, bool)>[];
          final abiertas = <Uri>[];
          debugPlanCheckoutCreator = ({required tier, required annual}) async {
            pedidos.add((tier, annual));
            return 'https://mp/checkout';
          };
          debugPlanCheckoutLauncher = (u) async {
            abiertas.add(u);
            return true;
          };
          addTearDown(() {
            debugPlanCheckoutCreator = null;
            debugPlanCheckoutLauncher = null;
          });

          final volver = find.text('REACTIVAR PLAN');

          // Mensual: es el ciclo por default del toggle.
          await tester.ensureVisible(volver);
          await tester.tap(volver);
          await tester.pumpAndSettle();
          expect(pedidos, [(SubscriptionTier.plan1, false)]);

          // Anual: el mismo botón, otro ciclo. El toggle queda arriba del
          // botón, así que hay que traerlo a la vista: el `ensureVisible` de
          // arriba pudo haber scrolleado la página y dejarlo fuera de pantalla
          // (un `tap` ahí falla en silencio, con un warning, y no cambia nada).
          await tester.ensureVisible(find.text(etiquetaAnual));
          await tester.tap(find.text(etiquetaAnual));
          await tester.pump();
          await tester.ensureVisible(volver);
          await tester.tap(volver);
          await tester.pumpAndSettle();

          expect(pedidos, [
            (SubscriptionTier.plan1, false),
            (SubscriptionTier.plan1, true),
          ]);
          expect(abiertas, hasLength(2));
        });

        // EL TEXTO EXACTO, y por qué es un «si». Si el primer cobro se difiere
        // lo decide el servidor, que además exige ver en MP un cobro real que
        // respalde esos días (`diferir-primer-cobro.ts`); desde el cliente eso
        // no se ve. La versión anterior decía «Pagado hasta el 15/10: el primer
        // cobro es ese día.» y afirmaba un pago que nadie había comprobado.
        testWidgets(
            'la nota es condicional: «Si ya pagaste hasta el d/m, el primer '
            'cobro es ese día.»', (tester) async {
          await pumpEn(tester, size, cancelado(conDiasPagos), web: true);

          const nota =
              'Si ya pagaste hasta el 15/10, el primer cobro es ese día.';
          expect(
            enElPieDe(SubscriptionTier.plan1, find.text(nota)),
            findsOneWidget,
          );
          // Una sola, en la tarjeta del plan actual y en ninguna otra.
          expect(find.textContaining('Si ya pagaste hasta'), findsOneWidget);
          // Y la afirmación incondicional de antes no volvió.
          expect(find.textContaining('Pagado hasta'), findsNothing);
        });

        // ── La nota y el borde de un día ──
        //
        // El servidor sólo difiere el primer cobro si falta AL MENOS un día:
        // con `finMs - nowMs < MIN_DIFERIMIENTO_MS` cobra en el acto
        // (`queda-menos-de-un-dia`, functions/src/subscriptions/mp/
        // diferir-primer-cobro.ts). Con menos, la nota sería falsa con
        // seguridad y no se dibuja. El botón NO depende del borde: volver a
        // suscribirse sigue siendo válido a una hora del vencimiento.
        //
        // El fin se mide contra el «ahora» congelado y no contra un instante
        // escrito a mano: el borde es una DIFERENCIA, no una fecha.
        for (final (descripcion, resta, conNota) in <(String, Duration, bool)>[
          ('14 días', const Duration(days: 14), true),
          ('24 h y 1 minuto', const Duration(hours: 24, minutes: 1), true),
          // El servidor descarta con `<`, no con `<=`: con EXACTAMENTE un día
          // todavía difiere.
          ('exactamente 24 h', const Duration(hours: 24), true),
          ('23 h 59 min', const Duration(hours: 23, minutes: 59), false),
          ('1 hora', const Duration(hours: 1), false),
          ('1 minuto', const Duration(minutes: 1), false),
        ]) {
          testWidgets(
              'con $descripcion por delante la nota '
              '${conNota ? 'aparece' : 'se esconde'} y el botón sigue',
              (tester) async {
            final fin = AppClock.now().add(resta).toUtc();
            await pumpEn(tester, size, cancelado(fin), web: true);

            expect(
              find.textContaining('Si ya pagaste hasta'),
              conNota ? findsOneWidget : findsNothing,
              reason: conNota
                  ? 'con $descripcion el servidor SÍ puede diferir y la nota '
                      'faltó'
                  : 'con $descripcion el servidor cobra en el acto y la nota '
                      'prometió lo contrario',
            );
            // Pase lo que pase con la nota, el plan se puede volver a
            // contratar: es la tarjeta del plan actual, dada de baja.
            expect(
              enElPieDe(SubscriptionTier.plan1, find.text('REACTIVAR PLAN')),
              findsOneWidget,
            );
            expect(find.text('TU PLAN ACTUAL'), findsNothing);
          });
        }

        // El botón y la nota son dos renglones nuevos en una tarjeta que ya
        // tenía el precio-héroe. Con el texto grande el botón crece y la nota
        // se parte en dos líneas: no puede desbordar. Un overflow de layout se
        // reporta durante el paint, así que `takeException()` es el chequeo.
        testWidgets('con textScale 1.5 ni el botón ni la nota desbordan',
            (tester) async {
          await pumpEn(
            tester,
            size,
            cancelado(conDiasPagos),
            web: true,
            textScale: 1.5,
          );

          expect(
            tester.takeException(),
            isNull,
            reason: 'la tarjeta de un plan dado de baja desborda con '
                'textScale 1.5',
          );
          expect(find.text('REACTIVAR PLAN'), findsOneWidget);
          expect(
            find.textContaining('Si ya pagaste hasta el 15/10'),
            findsOneWidget,
          );
        });

        // `currentPeriodEnd` es un instante UTC: entre las 21:00 y las 23:59
        // ART su día UTC ya es el siguiente. 01:30 UTC del 16 son las 22:30
        // ART del 15.
        testWidgets('la fecha se lee en calendario argentino, no en UTC',
            (tester) async {
          await pumpEn(
            tester,
            size,
            cancelado(DateTime.utc(2026, 10, 16, 1, 30)),
            web: true,
          );

          expect(
            find.text(
                'Si ya pagaste hasta el 15/10, el primer cobro es ese día.'),
            findsOneWidget,
          );
          expect(find.textContaining('16/10'), findsNothing);
        });

        // No está clavado en Plan 1: lo ofrece el tier que se dio de baja.
        testWidgets('lo ofrece el plan que se dio de baja, no otro',
            (tester) async {
          await pumpEn(
            tester,
            size,
            cancelado(conDiasPagos, tier: SubscriptionTier.plan2),
            web: true,
          );

          expect(
            enElPieDe(SubscriptionTier.plan2, find.text('REACTIVAR PLAN')),
            findsOneWidget,
          );
          expect(
            enElPieDe(SubscriptionTier.plan1, find.text('ELEGIR PLAN')),
            findsOneWidget,
          );
          expect(
            enElPieDe(SubscriptionTier.plan3, find.text('ELEGIR PLAN')),
            findsOneWidget,
          );
          expect(find.text('REACTIVAR PLAN'), findsOneWidget);
        });

        // Vencida, el plan ya no es el del PF: se vende como cualquier otro y
        // Free pasa a ser el actual.
        testWidgets(
            'con el período vencido el plan se elige como cualquier otro y '
            'Free es el actual', (tester) async {
          await pumpEn(tester, size, cancelado(vencido), web: true);

          expect(find.text('REACTIVAR PLAN'), findsNothing);
          expect(find.textContaining('Si ya pagaste hasta'), findsNothing);
          expect(
            enElPieDe(SubscriptionTier.plan1, find.text('ELEGIR PLAN')),
            findsOneWidget,
          );
          expect(find.text('ELEGIR PLAN'), findsNWidgets(3));
          expect(
            enElPieDe(SubscriptionTier.free, find.text('TU PLAN ACTUAL')),
            findsOneWidget,
          );
          expect(find.text('TU PLAN ACTUAL'), findsOneWidget);
        });

        // El servidor trata una baja sin fecha como ya vencida.
        testWidgets('una baja sin fecha de fin cuenta como vencida',
            (tester) async {
          await pumpEn(tester, size, cancelado(null), web: true);

          expect(find.text('REACTIVAR PLAN'), findsNothing);
          expect(find.text('ELEGIR PLAN'), findsNWidgets(3));
          expect(
            enElPieDe(SubscriptionTier.free, find.text('TU PLAN ACTUAL')),
            findsOneWidget,
          );
        });

        // REGRESIÓN: lo que no es una baja queda como estaba.
        testWidgets('un plan activo sigue siendo TU PLAN ACTUAL, sin botón',
            (tester) async {
          await pumpEn(
            tester,
            size,
            _trainer(tier: SubscriptionTier.plan1),
            web: true,
          );

          expect(
            enElPieDe(SubscriptionTier.plan1, find.text('TU PLAN ACTUAL')),
            findsOneWidget,
          );
          expect(find.text('REACTIVAR PLAN'), findsNothing);
          expect(find.textContaining('Si ya pagaste hasta'), findsNothing);
          expect(find.text('ELEGIR PLAN'), findsNWidgets(2));
        });

        // Sólo `cancelled` ofrece volver. Un `pending`, `paused` o `grace` es
        // otra historia (hay un cobro en curso o pausado): no se le ofrece
        // re-contratar encima, aunque el período del doc esté vencido.
        for (final status in SubscriptionStatus.values) {
          if (status == SubscriptionStatus.cancelled) continue;

          testWidgets('$status no ofrece reactivar el plan', (tester) async {
            await pumpEn(
              tester,
              size,
              _trainer(
                tier: SubscriptionTier.plan1,
                status: status,
                currentPeriodEnd: vencido,
              ),
              web: true,
            );

            expect(
              enElPieDe(SubscriptionTier.plan1, find.text('TU PLAN ACTUAL')),
              findsOneWidget,
            );
            expect(find.text('REACTIVAR PLAN'), findsNothing);
            expect(find.textContaining('Si ya pagaste hasta'), findsNothing);
          });
        }
      });
    }

    // ── App móvil: informa, no vende ─────────────────────────────────────────
    //
    // Los dos layouts, porque una tablet a 900pt entra por el ancho y sigue
    // siendo la app. Lo único que puede cambiar acá es QUÉ tarjeta lleva «TU
    // PLAN ACTUAL»; ni una palabra nueva, ni un botón, ni nada tappable.
    for (final (layout, size) in <(String, Size)>[
      ('angosto', _kMobileSize),
      ('ancho', _kTabletSize),
    ]) {
      group('móvil, layout $layout', () {
        testWidgets(
            'con días pagos sigue siendo TU PLAN ACTUAL: sin botón y sin '
            'texto nuevo', (tester) async {
          await pumpEn(tester, size, cancelado(conDiasPagos), web: false);

          expect(
            enElPieDe(SubscriptionTier.plan1, find.text('TU PLAN ACTUAL')),
            findsOneWidget,
          );
          expect(find.text('REACTIVAR PLAN'), findsNothing);
          expect(find.textContaining('Si ya pagaste hasta'), findsNothing);
          expect(find.textContaining('cobro'), findsNothing);
          expect(find.text('ELEGIR PLAN'), findsNothing);
          // El verbo de la compra no entra a la app móvil en ninguna forma.
          // Bajo 3.1.3(f) «reactivar» es un call to action igual que
          // «reactivalo» (`avisos_de_tope_movil_sin_llamado_a_comprar_test`,
          // que lo cuenta entre sus agujas con el stem «reactiva»); acá se
          // barre el stem sin distinguir mayúsculas, así que un copy nuevo con
          // otra conjugación cae igual.
          expect(
            tester
                .widgetList<Text>(find.byType(Text))
                .map((t) => (t.data ?? '').toLowerCase())
                .where((t) => t.contains('reactiv')),
            isEmpty,
            reason: 'la app móvil dice «reactivar» en algún renglón',
          );
          expect(
            enElPieDe(SubscriptionTier.plan1, find.byType(TreinoTappable)),
            findsNothing,
            reason: 'el plan actual dado de baja es tappable en la app móvil',
          );
        });

        // El guard que no depende de conocer los strings nuevos: una baja con
        // días pagos tiene que dibujar EXACTAMENTE lo mismo que el plan activo,
        // palabra por palabra y tappable por tappable. Cualquier cosa que
        // alguien cuelgue de la rama equivocada —un texto, un botón— rompe la
        // igualdad aunque se llame distinto a lo que hoy conocemos.
        testWidgets('dibuja lo mismo, palabra por palabra, que el plan activo',
            (tester) async {
          final activo = await fotoDe(
            tester,
            size,
            _trainer(tier: SubscriptionTier.plan1),
            web: false,
          );
          final baja = await fotoDe(
            tester,
            size,
            cancelado(conDiasPagos),
            web: false,
          );

          expect(baja.textos, activo.textos);
          expect(baja.tappables, activo.tappables);
        });

        testWidgets(
            'con el período vencido el plan pago ya no es el actual: lo es '
            'Free', (tester) async {
          await pumpEn(tester, size, cancelado(vencido), web: false);

          expect(
            enElPieDe(SubscriptionTier.plan1, find.text('TU PLAN ACTUAL')),
            findsNothing,
          );
          expect(
            enElPieDe(SubscriptionTier.free, find.text('TU PLAN ACTUAL')),
            findsOneWidget,
          );
          expect(find.text('TU PLAN ACTUAL'), findsOneWidget);
          // Sigue sin CTA en la tarjeta del plan pago (sin caja, sin espacio).
          expect(
            tester.getSize(find.byKey(const ValueKey('plan_cta_plan1'))),
            Size.zero,
          );
        });

        // Vencida, la pantalla es la de un PF Free: nada más cambia.
        testWidgets('con el período vencido dibuja lo mismo que un PF Free',
            (tester) async {
          final free = await fotoDe(tester, size, _trainer(), web: false);
          final baja =
              await fotoDe(tester, size, cancelado(vencido), web: false);

          expect(baja.textos, free.textos);
          expect(baja.tappables, free.tappables);
        });
      });
    }
  });
}

String _nombreDeTier(SubscriptionTier tier) => switch (tier) {
      SubscriptionTier.free => 'FREE',
      SubscriptionTier.plan1 => 'PLAN 1',
      SubscriptionTier.plan2 => 'PLAN 2',
      SubscriptionTier.plan3 => 'PLAN 3',
    };
