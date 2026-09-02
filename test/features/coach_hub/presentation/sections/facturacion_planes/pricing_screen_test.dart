import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:treino/core/widgets/motion/treino_tappable.dart';
import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/features/coach/domain/subscription_tier.dart';
import 'package:treino/features/coach/domain/trainer_subscription.dart';
import 'package:treino/features/coach_hub/presentation/sections/facturacion_planes/plan_checkout.dart';
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
        final carteles = <String>[
          'SE CONTRATA EN TREINO WEB',
          'El alta y el cambio de plan se hacen desde TREINO web, '
              'con esta misma cuenta.',
        ];

        for (final texto in carteles) {
          final cartel = find.text(texto);
          expect(
            cartel,
            findsWidgets,
            reason: 'no se encontró "$texto" — si el copy cambió, actualizá '
                'esta lista o el guard deja de estar cubierto',
          );

          for (final tipo in <Type>[TreinoTappable, GestureDetector, InkWell]) {
            expect(
              find.ancestor(of: cartel, matching: find.byType(tipo)),
              findsNothing,
              reason: 'la app móvil quedó tappable vía $tipo sobre "$texto": '
                  'sea lo que sea que abra, es un punto de compra adentro de '
                  'la app',
            );
          }
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

      // Y en su lugar, dónde se contrata. Sin «próximamente» (sería falso: en
      // la web ya se contrata) y sin nombrar a Apple.
      expect(find.text('SE CONTRATA EN TREINO WEB'), findsNWidgets(3));
      expect(
        find.textContaining('TREINO web'),
        findsWidgets,
        reason: 'el PF tiene que saber dónde se da de alta',
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
      expect(find.text('SE CONTRATA EN TREINO WEB'), findsNWidgets(3));
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

      final taps = tester
          .widgetList<TreinoTappable>(find.byType(TreinoTappable))
          .map((w) => w.onTap)
          .whereType<VoidCallback>()
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

      await tester.tap(find.text('ELEGIR PLAN').first);
      await tester.pump();

      expect(find.textContaining('Mercado Pago se habilita'), findsOneWidget);
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

      const prohibidos = <String>[
        'package:url_launcher',
        'launchUrl(',
        'launchUrlString(',
        'WebViewController',
        'WebViewWidget',
        'InAppBrowser',
      ];
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
        for (final aguja in prohibidos) {
          if (codigo.contains(aguja)) hallazgos.add('${f.path}: $aguja');
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
}

String _nombreDeTier(SubscriptionTier tier) => switch (tier) {
      SubscriptionTier.free => 'FREE',
      SubscriptionTier.plan1 => 'PLAN 1',
      SubscriptionTier.plan2 => 'PLAN 2',
      SubscriptionTier.plan3 => 'PLAN 3',
    };
