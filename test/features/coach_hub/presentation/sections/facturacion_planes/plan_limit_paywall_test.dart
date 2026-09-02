// El paywall tiene DOS formas con el MISMO contenido: dialog centrado en web
// (Coach Hub, app de escritorio con sidebar) y bottom sheet en movil.
//
// OJO al leer los tests de contenido de mas abajo: `kIsWeb` es una constante de
// COMPILACION y bajo `flutter test` (VM de Dart) vale `false` SIEMPRE. Sin
// override, entonces, la forma efectiva en todos estos tests es el SHEET. Los
// tests de copy que ya existian no cambiaron una linea, pero ahora corren
// contra la envoltura movil — que es exactamente lo que se quiere: el contenido
// no depende de la forma. La rama dialog se prueba fijando
// `debugPlanLimitPaywallForm`, el unico seam honesto que hay para eso.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:treino/features/coach/domain/subscription_tier.dart';
import 'package:treino/features/coach_hub/presentation/sections/facturacion_planes/plan_checkout.dart';
import 'package:treino/features/coach_hub/presentation/sections/facturacion_planes/plan_limit_paywall.dart';

/// iPhone 14/15 en puntos logicos.
const _kMobileSize = Size(390, 844);

/// iPhone SE — el telefono chico real contra el que hay que medir. Con
/// textScale de accesibilidad el contenido no entra ni cerca, que es justo el
/// caso que el sheet tiene que scrollear en vez de cortarse.
const _kShortPhoneSize = Size(375, 667);

/// Monta un botón que abre el paywall para [tier], dentro de un router mínimo
/// (el CTA "VER PLANES" hace context.push).
Widget _harness(
  SubscriptionTier tier, {
  PlanLimitReason reason = PlanLimitReason.planLimit,
  SubscriptionStatus? subscriptionStatus,
  String? billingRoute,
  double textScale = 1.0,
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
  return MaterialApp.router(
    routerConfig: router,
    // `builder` envuelve al Navigator, asi que las rutas (y los popups que
    // cuelgan de el) heredan este MediaQuery. Es la unica forma de forzar el
    // textScaler sin pelearse con el `MediaQuery.fromView` de WidgetsApp.
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
  );
}

/// Observador que cuenta cuantos `ModalBottomSheetRoute` se empujaron sobre
/// SU navigator. Sirve para pinear en cual de los dos aterriza el sheet.
class _SheetRouteSpy extends NavigatorObserver {
  int pushedSheets = 0;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is ModalBottomSheetRoute) pushedSheets++;
    super.didPush(route, previousRoute);
  }
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
    // Fija la superficie que SI cobra. La combinacion «app movil + ruta de
    // facturacion» no existe en produccion —los tres callsites que pasan
    // `billingRoute` son del Coach Hub— y antes este test la ejercitaba sin
    // querer, porque bajo `flutter test` la superficie real es movil.
    debugPlanCheckout = planCheckoutFor(isWeb: true);
    addTearDown(() => debugPlanCheckout = null);

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

  // EL OTRO PUNTO DE ENTRADA AL COBRO.
  //
  // El guard de superficie vivia SOLO en la pricing page, y este CTA es el que
  // ve el PF con la suscripcion pausada cuando acepta una solicitud DESDE EL
  // TELEFONO (`trainer_dashboard_tab`, `trainer_coach_view`). Es exactamente
  // donde alguien va a cablear la reactivacion con Mercado Pago: reactivar es
  // la mitad del negocio de una suscripcion.
  //
  // Antes lo unico que decidia era `billingRoute == null` — un string. Este
  // test pinea que lo decide la SUPERFICIE: aunque le pases una ruta de
  // facturacion, en la app no se llega a pagar. Sin el guard en `_PrimaryCta`
  // este test navega y se pone rojo.
  testWidgets('en la app REGULARIZAR no navega ni con billingRoute',
      (tester) async {
    // Sin override: la superficie REAL de `flutter test` es la movil.
    expect(debugPlanCheckout, isNull, reason: 'un test anterior no limpio');

    await tester.pumpWidget(_harness(
      SubscriptionTier.plan1,
      reason: PlanLimitReason.subscriptionInactive,
      billingRoute: '/ajustes',
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('REGULARIZAR'));
    await tester.pumpAndSettle();

    expect(
      find.text('AJUSTES'),
      findsNothing,
      reason: 'la app movil llego a una vista de facturacion: es el camino por '
          'el que entra el cobro de reactivacion',
    );
    expect(find.byType(SnackBar), findsOneWidget);
  });

  testWidgets('reason por defecto es plan-limit — comportamiento intacto',
      (tester) async {
    // La firma es ADITIVA: los callsites viejos (paywall_preview_screen)
    // siguen compilando y renderizando exactamente igual.
    await open(tester, SubscriptionTier.free);

    expect(find.text('PASATE A PLAN 1'), findsOneWidget);
    expect(find.text('REGULARIZAR'), findsNothing);
  });

  // ── Forma: sheet en movil, dialog en web ─────────────────────────────────
  //
  // Un bottom sheet en una app de escritorio con sidebar es un error de
  // plataforma; un dialog centrado en un telefono deja el CTA lejos del pulgar
  // y sin el gesto de descarte que el sistema ya ensenio. Son DOS envolturas,
  // no una "responsive".

  group('forma del paywall', () {
    /// Fija la forma y la devuelve a `null` al terminar, para no filtrar el
    /// override al test siguiente.
    void useForm(PlanLimitPaywallForm form) {
      debugPlanLimitPaywallForm = form;
      addTearDown(() => debugPlanLimitPaywallForm = null);
    }

    testWidgets('en movil sube como bottom sheet, no como Dialog',
        (tester) async {
      useForm(PlanLimitPaywallForm.sheet);
      await open(tester, SubscriptionTier.free);

      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.byType(Dialog), findsNothing);
    });

    testWidgets('en web es un Dialog centrado, no un sheet', (tester) async {
      useForm(PlanLimitPaywallForm.dialog);
      await open(tester, SubscriptionTier.free);

      expect(find.byType(Dialog), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);
    });

    testWidgets('sin override manda la plataforma — en la VM, sheet',
        (tester) async {
      // `kIsWeb` es false bajo `flutter test`. Este test pinea que el default
      // NO quedo clavado en una forma: si alguien invierte la condicion, se
      // cae aca.
      expect(debugPlanLimitPaywallForm, isNull);
      await open(tester, SubscriptionTier.free);

      expect(find.byType(BottomSheet), findsOneWidget);
    });

    testWidgets(
        'el sheet va pegado al borde inferior, a ancho completo y '
        'redondeado solo arriba', (tester) async {
      tester.view.physicalSize = _kMobileSize;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      useForm(PlanLimitPaywallForm.sheet);

      await open(tester, SubscriptionTier.free);

      final rect = tester.getRect(find.byType(BottomSheet));
      expect(rect.left, 0, reason: 'el sheet no llega al borde izquierdo');
      expect(rect.right, _kMobileSize.width,
          reason: 'el sheet no llega al borde derecho');
      expect(rect.bottom, _kMobileSize.height,
          reason: 'el sheet no esta pegado al borde inferior');

      // Solo las esquinas de ARRIBA. Un sheet con las cuatro redondeadas deja
      // dos muescas contra el borde de la pantalla.
      final box = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(BottomSheet),
              matching: find.byType(Container),
            )
            .first,
      );
      expect(
        (box.decoration! as BoxDecoration).borderRadius,
        const BorderRadius.vertical(top: Radius.circular(28)),
      );
    });

    testWidgets('"Ahora no" cierra el sheet', (tester) async {
      useForm(PlanLimitPaywallForm.sheet);
      await open(tester, SubscriptionTier.free);
      expect(find.byType(BottomSheet), findsOneWidget);

      await tester.tap(find.text('Ahora no'));
      await tester.pumpAndSettle();

      expect(find.byType(BottomSheet), findsNothing);
      expect(find.text('LLEGASTE AL LÍMITE DE TU PLAN'), findsNothing);
    });
  });

  // ── Mismo contenido en las dos formas ────────────────────────────────────
  //
  // El punto entero de haber extraido el cuerpo a un widget compartido: si
  // alguien toca el copy en una envoltura y no en la otra, web y movil empiezan
  // a decir cosas distintas. Este barrido cruza las 3 ramas visuales por las 2
  // formas y exige los mismos textos.

  group('el contenido no depende de la forma', () {
    final ramas = <({
      String nombre,
      SubscriptionTier tier,
      PlanLimitReason reason,
      List<String> textos,
    })>[
      (
        nombre: 'upsell al siguiente tier',
        tier: SubscriptionTier.free,
        reason: PlanLimitReason.planLimit,
        textos: [
          'LLEGASTE AL LÍMITE DE TU PLAN',
          'PASATE A PLAN 1',
          '12.000',
          'Hasta 7 alumnos',
          'VER PLANES',
          'Ahora no',
        ],
      ),
      (
        nombre: 'plan a medida (tope)',
        tier: SubscriptionTier.plan3,
        reason: PlanLimitReason.planLimit,
        textos: [
          'LLEGASTE AL LÍMITE DE TU PLAN',
          'PLAN A MEDIDA',
          'CONTACTANOS',
          'Ahora no',
        ],
      ),
      (
        nombre: 'suscripcion suspendida',
        tier: SubscriptionTier.plan1,
        reason: PlanLimitReason.subscriptionInactive,
        textos: [
          'TU SUSCRIPCIÓN ESTÁ SUSPENDIDA',
          'TU PLAN: PLAN 1',
          'REGULARIZAR',
          'Ahora no',
        ],
      ),
    ];

    for (final rama in ramas) {
      for (final form in PlanLimitPaywallForm.values) {
        testWidgets('${rama.nombre} dice lo mismo en ${form.name}',
            (tester) async {
          debugPlanLimitPaywallForm = form;
          addTearDown(() => debugPlanLimitPaywallForm = null);

          await tester.pumpWidget(_harness(rama.tier, reason: rama.reason));
          await tester.tap(find.text('open'));
          await tester.pumpAndSettle();

          for (final texto in rama.textos) {
            expect(
              find.text(texto),
              findsOneWidget,
              reason: '«$texto» falta en la forma ${form.name}',
            );
          }
        });
      }
    }
  });

  // ── Accesibilidad: textScale alto ────────────────────────────────────────
  //
  // Un sheet de altura fija con el texto agrandado se CORTA: el "Ahora no" y
  // el CTA quedan fuera de pantalla y el usuario se come un modal del que no
  // puede salir salvo por el gesto del sistema. El techo de altura + el
  // scroll interno son la diferencia entre eso y una pantalla usable.

  group('textScale de accesibilidad', () {
    setUp(() {
      debugPlanLimitPaywallForm = PlanLimitPaywallForm.sheet;
      addTearDown(() => debugPlanLimitPaywallForm = null);
    });

    for (final scale in <double>[1.0, 1.5, 2.0]) {
      testWidgets('el sheet no desborda con textScale $scale', (tester) async {
        tester.view.physicalSize = _kShortPhoneSize;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          _harness(SubscriptionTier.free, textScale: scale),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();

        // Un overflow de layout se reporta a `FlutterError.onError` durante el
        // paint y el harness lo convierte en excepcion pendiente, asi que
        // `takeException()` es el chequeo real.
        expect(
          tester.takeException(),
          isNull,
          reason: 'el sheet desborda con textScale $scale',
        );
      });
    }

    testWidgets(
        'con textScale 1.5 el sheet SCROLLEA y el CTA sigue siendo '
        'alcanzable', (tester) async {
      tester.view.physicalSize = _kShortPhoneSize;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_harness(SubscriptionTier.free, textScale: 1.5));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      final position = tester
          .state<ScrollableState>(
            find.descendant(
              of: find.byType(BottomSheet),
              matching: find.byType(Scrollable),
            ),
          )
          .position;

      // Si esto es 0 el contenido entro entero y el test no probo nada: subir
      // el textScale o achicar el viewport hasta que vuelva a ser > 0.
      expect(
        position.maxScrollExtent,
        greaterThan(0),
        reason: 'el contenido entra sin scrollear — el test no prueba nada',
      );

      await tester.ensureVisible(find.text('Ahora no'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ahora no'));
      await tester.pumpAndSettle();

      expect(find.byType(BottomSheet), findsNothing);
    });
  });

  // ── El sheet vive en el Navigator RAIZ ───────────────────────────────────
  //
  // `showModalBottomSheet` defaultea a `useRootNavigator: false`. En la app
  // movil eso lo montaria en el Navigator del ShellRoute, que vive DENTRO del
  // `Scaffold.body` del shell: el sheet quedaria recortado al body, con la
  // bottom bar flotando encima y el scrim sin taparla. El `showDialog` de antes
  // ya iba al raiz (es SU default), asi que esto ademas mantiene la paridad.

  testWidgets('el sheet se monta en el Navigator RAIZ, no en el anidado',
      (tester) async {
    debugPlanLimitPaywallForm = PlanLimitPaywallForm.sheet;
    addTearDown(() => debugPlanLimitPaywallForm = null);

    final root = _SheetRouteSpy();
    final anidado = _SheetRouteSpy();
    late BuildContext contextAnidado;

    await tester.pumpWidget(MaterialApp(
      navigatorObservers: [root],
      home: Navigator(
        observers: [anidado],
        onGenerateRoute: (_) => MaterialPageRoute<void>(
          builder: (ctx) {
            contextAnidado = ctx;
            return const Scaffold(body: SizedBox.shrink());
          },
        ),
      ),
    ));

    unawaited(showPlanLimitPaywall(
      contextAnidado,
      currentTier: SubscriptionTier.free,
    ));
    await tester.pumpAndSettle();

    expect(find.byType(BottomSheet), findsOneWidget);
    expect(
      root.pushedSheets,
      1,
      reason: 'el sheet no llego al Navigator raiz — falta useRootNavigator',
    );
    expect(
      anidado.pushedSheets,
      0,
      reason: 'el sheet quedo atrapado en el Navigator anidado',
    );
  });
}
