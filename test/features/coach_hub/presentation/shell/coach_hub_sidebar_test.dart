import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:treino/app/theme/app_motion.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/app/theme/tokens/components/coach_hub_layout_tokens.dart';
import 'package:treino/app/theme/tokens/components/coach_hub_sidebar_item_tokens.dart';
import 'package:treino/app/theme/tokens/components/treino_badge_tokens.dart';
import 'package:treino/core/persistence/shared_prefs_provider.dart';
import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/core/widgets/motion/treino_fade_slide_in.dart';
import 'package:treino/features/coach_hub/presentation/shell/coach_hub_sidebar.dart';
import 'package:treino/features/coach_hub/presentation/shell/navigator_semantics_boundary.dart';
import 'package:treino/features/coach_hub/presentation/shell/sidebar_item.dart';
import 'package:treino/features/coach_hub/presentation/shell/sidebar_registry.dart';
import 'package:treino/core/widgets/treino_logo.dart';

/// Monta el sidebar dentro de un `ShellRoute` real (necesita `GoRouterState`).
/// Resuelve las prefs en el cuerpo del test y overridea
/// `sharedPreferencesProvider` con un future ya completo → estado colapsado
/// determinista, sin depender del timing del method channel.
Future<void> _pumpSidebar(
  WidgetTester tester, {
  Map<String, Object> prefs = const {},
  String initial = '/dashboard',
  ThemeData? theme,
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final sp = await SharedPreferences.getInstance();
  final paths = {
    ...sidebarRegistry.map((i) => i.route),
    '/ajustes',
  }.toList();

  final router = GoRouter(
    initialLocation: initial,
    routes: [
      ShellRoute(
        builder: (ctx, state, child) => Scaffold(
          body: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const CoachHubSidebar(),
              Expanded(child: NavigatorSemanticsBoundary(child: child))
            ],
          ),
        ),
        routes: [
          for (final p in paths)
            GoRoute(path: p, builder: (_, __) => Text('page:$p')),
        ],
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWith((ref) => Future.value(sp)),
      ],
      child: MaterialApp.router(
        theme: theme ?? AppTheme.dark(),
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Finder del ícono de la PRIMERA fila de navegación.
///
/// Anclado a la key de la fila y no a `find.byType(Icon).first`: ese primer
/// ícono del árbol es el toggle del header, que está a 114px de acá y también
/// se mueve al colapsar. O sea que un test escrito contra él pasa —pero por el
/// widget equivocado, y dejaría de proteger lo que dice proteger.
Finder _primerItemIcono() => find.descendant(
      of: find.byKey(ValueKey(sidebarRegistry.first.route)),
      matching: find.byType(Icon),
    );

/// Finder del label de la primera fila de navegación, por la misma razón.
Finder _primerItemLabel() => find.descendant(
      of: find.byKey(ValueKey(sidebarRegistry.first.route)),
      matching: find.byType(Text),
    );

/// Borde izquierdo del bloque de label de un item, en coordenadas del sidebar.
///
/// Colapsado el label sigue MONTADO: no desaparece, se DESLIZA hasta pasar el
/// borde de los 72px, donde el `clipBehavior` del contenedor lo tapa. O sea que
/// `findsNothing` dejó de ser la pregunta correcta — lo que importa no es si
/// está en el árbol, es dónde está parado respecto del borde que lo recorta.
///
/// Se mide posición y no opacidad a propósito. Un `AnimatedOpacity` parece la
/// respuesta obvia y no lo es: su valor actual vive en un `FadeTransition`
/// interno, y leerlo desde el test obliga a adivinar cuál de los seis fades que
/// hay encima de este texto —`Tooltip` trae los suyos, `TreinoFadeSlideIn` el
/// suyo— es el que corresponde. Adivinar mal da 0.0, que es indistinguible de
/// una animación rota: el test pasaría a mentir en la dirección peligrosa. La
/// posición se lee de la geometría, sin ambigüedad posible.
double _labelLeft(WidgetTester tester, String label) {
  return tester.getTopLeft(find.text(label)).dx;
}

/// `true` si el label quedó del lado de afuera del clip del sidebar colapsado.
bool _labelOculto(WidgetTester tester, String label) {
  return _labelLeft(tester, label) >=
      CoachHubLayoutTokens.sidebarCollapsedWidth;
}

void main() {
  testWidgets('CONTROL: sin hover no hay ningun Text vacio en el sidebar',
      (tester) async {
    await _pumpSidebar(tester);
    expect(find.text('', findRichText: true), findsNothing);
  });

  testWidgets('expandido, el hover NO deja un tooltip vacío en pantalla',
      (tester) async {
    // El PF mandó una captura de un CUADRADO OSCURO flotando entre dos items
    // del sidebar. Es un `Tooltip` con `message: ''`: se centra sobre su
    // target y cae 24 px abajo, o sea justo en el hueco entre el item que se
    // hoverea y el de abajo.
    //
    // El comentario de `coach_hub_sidebar.dart` afirmaba que «el Tooltip con
    // mensaje vacío no se muestra». No es cierto: Flutter no chequea el
    // mensaje, arma la burbuja igual y queda una caja sin texto.
    await _pumpSidebar(tester); // expandido: los labels ya se leen

    final item = find.text('Chat');
    expect(item, findsOneWidget);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(() => mouse.removePointer());
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(item));
    await tester.pump();
    // `waitDuration` del tooltip es 200 ms.
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      find.text('', findRichText: true),
      findsNothing,
      reason: 'expandido el label ya está en pantalla: no va ninguna burbuja',
    );
  });

  testWidgets(
      'expandido → 240px, header con el wordmark, 2 headers (GESTIÓN, RECURSOS) y '
      'todos los labels del registry [SCENARIO-750]', (tester) async {
    await _pumpSidebar(tester);

    final size =
        tester.getSize(find.byKey(const Key('coach_hub_sidebar_container')));
    expect(size.width, CoachHubLayoutTokens.sidebarExpandedWidth);
    expect(size.width, 240);

    expect(find.byType(TreinoLogo), findsOneWidget);

    // W2 reduce 2026-07-02: el sidebar pasó a 2 grupos activos (GESTIÓN y
    // RECURSOS). Cuenta se abre solamente desde la fila del perfil. Reportes
    // salió del registry — sin scope de producto todavía. Los grupos
    // legacy siguen existiendo en el enum para no romper items futuros
    // pero no se renderean porque no tienen items en el registry.
    for (final header in ['GESTIÓN', 'RECURSOS']) {
      expect(find.text(header), findsOneWidget, reason: header);
    }
    for (final empty in [
      'CUENTA',
      'RESUMEN',
      'ALUMNOS',
      'PLAN',
      'WELLNESS',
      'NEGOCIO',
      'COMUNICACIÓN',
    ]) {
      expect(find.text(empty), findsNothing, reason: 'empty group $empty');
    }

    for (final item in sidebarRegistry) {
      expect(find.text(item.label), findsOneWidget, reason: item.label);
    }
    expect(find.text('Ajustes'), findsNothing);
  });

  testWidgets(
      'colapsado → 72px, header/headers/labels ocultos, avatar sigue visible '
      '[SCENARIO-754]', (tester) async {
    await _pumpSidebar(tester, prefs: {'coach_hub.sidebar.collapsed': true});

    final size =
        tester.getSize(find.byKey(const Key('coach_hub_sidebar_container')));
    expect(size.width, CoachHubLayoutTokens.sidebarCollapsedWidth);
    expect(size.width, 72);

    expect(find.byType(TreinoLogo), findsNothing);
    expect(find.text('RESUMEN'), findsNothing);
    // El label no se VE —quedó afuera del clip— aunque siga en el árbol para
    // poder deslizarse. Ver `_labelOculto`.
    expect(_labelOculto(tester, 'Dashboard'), isTrue);
    expect(find.byType(Icon), findsWidgets);
    // El avatar del perfil sigue visible, centrado, sin nombre/subtítulo.
    expect(find.byType(CircleAvatar), findsOneWidget);
  });

  testWidgets('tap en item navega via context.go [SCENARIO-752]',
      (tester) async {
    await _pumpSidebar(tester);

    await tester.tap(find.text('Alumnos'));
    await tester.pumpAndSettle();

    expect(find.text('page:/alumnos'), findsOneWidget);
  });

  testWidgets(
      'item activo (Dashboard en /dashboard) usa AnimatedContainer para la '
      'píldora — ADR-SH-004', (tester) async {
    await _pumpSidebar(tester);

    // El label activo se pinta con weight 600 (vs 400 inactivo).
    final dashboardText = tester.widget<Text>(find.text('Dashboard'));
    expect(dashboardText.style?.fontWeight, FontWeight.w600);

    final alumnosText = tester.widget<Text>(find.text('Alumnos'));
    expect(alumnosText.style?.fontWeight, FontWeight.w400);

    // La píldora activa vive dentro de un AnimatedContainer (motion token).
    final pillFinder = find.ancestor(
      of: find.text('Dashboard'),
      matching: find.byType(AnimatedContainer),
    );
    expect(pillFinder, findsWidgets);

    // REQ-SH-003a: variante elegida = píldora completa (relleno bgCard en
    // todo el ancho de la fila), no barra lateral. El AnimatedContainer más
    // interno (el que aplica el fondo/radius) debe tener el color/radio del
    // token activo.
    final tokens = CoachHubSidebarItemTokens.of(
      tester.element(find.text('Dashboard')),
    );
    final pill = tester.widget<AnimatedContainer>(pillFinder.first);
    final decoration = pill.decoration as BoxDecoration;
    expect(decoration.color, tokens.activeBackground);
    expect(
      decoration.borderRadius,
      BorderRadius.circular(CoachHubSidebarItemTokens.borderRadius),
    );

    // NO debe existir la barra lateral de 3px de acento — variante
    // descartada por REQ-SH-003a (el mockup muestra relleno completo).
    final leftBar = find.byWidgetPredicate(
      (w) =>
          w is Container &&
          w.constraints == null &&
          (w.decoration is BoxDecoration) &&
          ((w.decoration as BoxDecoration).borderRadius ==
              BorderRadius.circular(2)),
    );
    expect(leftBar, findsNothing);
  });

  testWidgets(
      'el toggle (junto al wordmark) contrae/expande al tocarlo — '
      'REQ-SH-006', (tester) async {
    await _pumpSidebar(tester); // expandido
    expect(
      tester
          .getSize(find.byKey(const Key('coach_hub_sidebar_container')))
          .width,
      240,
    );
    expect(find.byTooltip('Contraer menú'), findsOneWidget);

    await tester.tap(find.byKey(const Key('sidebar_toggle_button')));
    await tester.pumpAndSettle();

    expect(
      tester
          .getSize(find.byKey(const Key('coach_hub_sidebar_container')))
          .width,
      72,
    );
    expect(find.byTooltip('Expandir menú'), findsOneWidget);
  });

  testWidgets('el toggle vive arriba, junto al wordmark', (tester) async {
    await _pumpSidebar(tester);

    final logoTop = tester.getTopLeft(find.byType(TreinoLogo)).dy;
    final toggleTop =
        tester.getTopLeft(find.byKey(const Key('sidebar_toggle_button'))).dy;
    final profileTop =
        tester.getTopLeft(find.byKey(const Key('sidebar_profile_row'))).dy;

    expect((toggleTop - logoTop).abs(), lessThan(20));
    expect(toggleTop, lessThan(profileTop));
  });

  testWidgets(
      'colapsado → el toggle está habilitado, apunta a expandir y NO está '
      'fusionado con el header de grupo (REQ-SH-004/006)', (tester) async {
    await _pumpSidebar(tester, prefs: {'coach_hub.sidebar.collapsed': true});

    final toggle = tester.widget<IconButton>(
      find.byKey(const Key('sidebar_toggle_button')),
    );
    expect(toggle.onPressed, isNotNull); // se puede re-expandir
    expect((toggle.icon as Icon).icon, TreinoIcon.menu);
    // El header GESTIÓN ya no aparece en absoluto colapsado (no hay toggle
    // fusionado que lo mantenga visible).
    expect(find.text('GESTIÓN'), findsNothing);
  });

  testWidgets('footer muestra avatar + nombre + plan — REQ-SH-005',
      (tester) async {
    await _pumpSidebar(tester);

    expect(find.byKey(const Key('sidebar_profile_row')), findsOneWidget);
    expect(find.byType(CircleAvatar), findsOneWidget);
    // chevronRight y NO chevronDown: la fila navega a /ajustes, no abre un
    // menú. El chevron hacia abajo prometía un desplegable inexistente.
    expect(find.byIcon(TreinoIcon.chevronRight), findsOneWidget);
    expect(find.byIcon(TreinoIcon.chevronDown), findsNothing);
    // Sin perfil cargado el tier cae a Free (sin backfill), igual que en
    // Facturación — antes acá había un literal "Cuenta profesional" que
    // mostraba lo mismo a un PF en Free que a uno en Plan 3.
    expect(find.text('Plan Free'), findsOneWidget);
    expect(find.text('Cuenta profesional'), findsNothing);
  });

  testWidgets('footer expandido → tocar el perfil navega a /ajustes',
      (tester) async {
    await _pumpSidebar(tester);

    await tester.tap(find.byKey(const Key('sidebar_profile_row')));
    await tester.pumpAndSettle();

    expect(find.text('page:/ajustes'), findsOneWidget);
  });

  testWidgets('footer colapsado → el avatar sigue siendo el acceso a la cuenta',
      (tester) async {
    await _pumpSidebar(tester, prefs: {'coach_hub.sidebar.collapsed': true});

    // Colapsado no hay fila: el target es el avatar, con tooltip propio.
    expect(find.byKey(const Key('sidebar_profile_row')), findsNothing);
    final avatar = find.byKey(const Key('sidebar_profile_avatar'));
    expect(avatar, findsOneWidget);

    await tester.tap(avatar);
    await tester.pumpAndSettle();

    expect(find.text('page:/ajustes'), findsOneWidget);
  });

  testWidgets('entrada del shell usa TreinoFadeSlideIn (REQ-SH-010)',
      (tester) async {
    await _pumpSidebar(tester);
    expect(find.byType(TreinoFadeSlideIn), findsWidgets);
  });

  testWidgets(
      'reduce-motion → sin animación de entrada visible tras el primer frame',
      (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);

    await _pumpSidebar(tester);

    // Con reduce-motion, TreinoFadeSlideIn salta directo a opacidad 1 sin
    // necesidad de pumpAndSettle adicional — ya lo hace _pumpSidebar.
    expect(find.text('Dashboard'), findsOneWidget);
  });

  testWidgets('smoke visual en tema claro (mintMagentaLight) — REQ-SH-011',
      (tester) async {
    await _pumpSidebar(tester, theme: AppTheme.light());
    expect(find.byType(TreinoLogo), findsOneWidget);
    expect(find.text('Dashboard'), findsOneWidget);
  });

  testWidgets(
      'badge numérico se renderiza cuando el item expone badgeProvider '
      '(Pagos/Chat, ADR-SH-004)', (tester) async {
    final testBadgeProvider = StateProvider<int?>((ref) => 3);
    final item = sidebarRegistry.firstWhere((i) => i.id == 'pagos');
    final badgedItem = SidebarItem(
      id: item.id,
      label: item.label,
      route: item.route,
      iconBuilder: item.iconBuilder,
      group: item.group,
      badgeProvider: testBadgeProvider,
    );

    SharedPreferences.setMockInitialValues({});
    final sp = await SharedPreferences.getInstance();
    final router = GoRouter(
      initialLocation: '/pagos',
      routes: [
        ShellRoute(
          builder: (ctx, state, child) => Scaffold(
            body: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                CoachHubSidebar(itemsOverride: [badgedItem]),
                Expanded(child: NavigatorSemanticsBoundary(child: child)),
              ],
            ),
          ),
          routes: [
            GoRoute(path: '/pagos', builder: (_, __) => const Text('pagos')),
          ],
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWith((ref) => Future.value(sp)),
        ],
        child: MaterialApp.router(theme: AppTheme.dark(), routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('3'), findsOneWidget);

    // El badge usa los tokens semánticos (highlight magenta + texto claro),
    // no colores hardcodeados — ADR-SH-003/mockup sidebar.png.
    final badgeTokens = TreinoBadgeTokens.of(tester.element(find.text('3')));
    final badgeContainer = tester.widget<Container>(
      find
          .ancestor(
            of: find.text('3'),
            matching: find.byType(Container),
          )
          .first,
    );
    final badgeDecoration = badgeContainer.decoration as BoxDecoration;
    expect(badgeDecoration.color, badgeTokens.background);
    final badgeText = tester.widget<Text>(find.text('3'));
    expect(badgeText.style?.color, badgeTokens.foreground);
  });

  // ─── Sidebar colapsado: nombre y aviso ────────────────────────────────────
  //
  // Colapsado, el `if (!collapsed)` que oculta el label ocultaba TAMBIÉN el
  // badge, sin nada que lo reemplace. Los dos únicos items que lo exponen son
  // Invitaciones (solicitudes pendientes) y Pagos (cobros), y entre 768 y
  // 1279 px el colapso lo FUERZA el shell (`Viewport.compact`): el PF no
  // eligió colapsar, no puede expandir, y perdía el único aviso de la
  // pantalla. Estos tests fijan las dos ramas que faltaban.

  testWidgets(
      'colapsado con badge → punto sobre el ícono; el número no entra pero el '
      'aviso no se pierde', (tester) async {
    final testBadgeProvider = StateProvider<int?>((ref) => 3);
    final item = sidebarRegistry.firstWhere((i) => i.id == 'pagos');

    await _pumpSidebarWithItems(
      tester,
      items: [
        SidebarItem(
          id: item.id,
          label: item.label,
          route: item.route,
          iconBuilder: item.iconBuilder,
          group: item.group,
          badgeProvider: testBadgeProvider,
        ),
      ],
      prefs: {'coach_hub.sidebar.collapsed': true},
      initial: '/pagos',
    );

    // El número no cabe en 72px: el badge se degrada a punto.
    // El número del badge viaja con el label: montado, pero invisible.
    expect(_labelOculto(tester, '3'), isTrue);

    final tokens =
        TreinoBadgeTokens.of(tester.element(find.byType(Icon).first));
    final dot = find.byWidgetPredicate(
      (w) =>
          w is Container &&
          w.decoration is BoxDecoration &&
          (w.decoration as BoxDecoration).shape == BoxShape.circle &&
          (w.decoration as BoxDecoration).color == tokens.background,
    );
    expect(dot, findsOneWidget);
  });

  testWidgets('colapsado sin badge → el ícono va pelado, sin punto fantasma',
      (tester) async {
    await _pumpSidebar(tester, prefs: {'coach_hub.sidebar.collapsed': true});

    final tokens =
        TreinoBadgeTokens.of(tester.element(find.byType(Icon).first));
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is Container &&
            w.decoration is BoxDecoration &&
            (w.decoration as BoxDecoration).shape == BoxShape.circle &&
            (w.decoration as BoxDecoration).color == tokens.background,
      ),
      findsNothing,
    );
  });

  testWidgets(
      'colapsado → cada item se nombra por tooltip (el label no está en '
      'pantalla)', (tester) async {
    await _pumpSidebar(tester, prefs: {'coach_hub.sidebar.collapsed': true});

    // Precondición: el label NO se pinta. Sin tooltip, el item es un glifo
    // anónimo — y entre 768 y 1279 px el colapso lo fuerza el shell.
    expect(_labelOculto(tester, 'Dashboard'), isTrue);
    expect(_labelOculto(tester, 'Alumnos'), isTrue);

    for (final item in sidebarRegistry) {
      expect(
        find.byTooltip(item.label),
        findsOneWidget,
        reason: 'sin tooltip, «${item.label}» es un ícono sin nombre',
      );
    }
  });

  testWidgets('colapsado con badge → el conteo viaja en el tooltip',
      (tester) async {
    final testBadgeProvider = StateProvider<int?>((ref) => 3);
    final item = sidebarRegistry.firstWhere((i) => i.id == 'pagos');

    await _pumpSidebarWithItems(
      tester,
      items: [
        SidebarItem(
          id: item.id,
          label: item.label,
          route: item.route,
          iconBuilder: item.iconBuilder,
          group: item.group,
          badgeProvider: testBadgeProvider,
        ),
      ],
      prefs: {'coach_hub.sidebar.collapsed': true},
      initial: '/pagos',
    );

    // El punto dice «hay algo»; el número solo lo dice el tooltip.
    expect(find.byTooltip('${item.label} (3)'), findsOneWidget);
  });

  // Estos dos asserts estuvieron un tiempo escritos como una NOTA que explicaba
  // por qué no se podían escribir: el sidebar entero aportaba CERO nodos al
  // árbol de semántica, así que `bySemanticsLabel` no encontraba nada ni
  // colapsado ni expandido. No era del sidebar — el `Navigator` de la sección
  // le borraba la semántica a todos sus hermanos anteriores. Ver
  // [NavigatorSemanticsBoundary], que es lo que el harness de acá arriba monta
  // igual que el `CoachHubScaffold` de producción.
  //
  // El guard de que producción tiene esa frontera vive en
  // `coach_hub_scaffold_test.dart`, montando el shell real: sin él, estos dos
  // asserts sólo probarían el harness.

  testWidgets('colapsado → el label del ítem llega al árbol de semántica',
      (tester) async {
    final handle = tester.ensureSemantics();
    await _pumpSidebar(tester, prefs: {'coach_hub.sidebar.collapsed': true});

    // Colapsado no hay un solo `Text` en la fila: el nombre existe únicamente
    // como label de semántica. Si esto se rompe, el ítem es un ícono anónimo.
    expect(find.bySemanticsLabel('Dashboard'), findsOneWidget);

    handle.dispose();
  });

  testWidgets('colapsado con badge → el conteo también entra en el label',
      (tester) async {
    final handle = tester.ensureSemantics();
    final testBadgeProvider = StateProvider<int?>((ref) => 3);
    final item = sidebarRegistry.firstWhere((i) => i.id == 'pagos');

    await _pumpSidebarWithItems(
      tester,
      items: [
        SidebarItem(
          id: item.id,
          label: item.label,
          route: item.route,
          iconBuilder: item.iconBuilder,
          group: item.group,
          badgeProvider: testBadgeProvider,
        ),
      ],
      prefs: {'coach_hub.sidebar.collapsed': true},
      initial: '/pagos',
    );

    // El tooltip dice el conteo al mouse; el label lo dice al lector.
    expect(find.bySemanticsLabel('${item.label}, 3'), findsOneWidget);

    handle.dispose();
  });

  // ─── El colapso ANIMA ─────────────────────────────────────────────────────
  //
  // El ancho del sidebar ya animaba sus 240→72px, pero el contenido cambiaba en
  // el primer frame: el contenedor se deslizaba suave sobre un label que ya no
  // estaba, y el conjunto se leía como un salto con un deslizamiento al lado.

  testWidgets('el label se desliza afuera en vez de desaparecer de golpe',
      (tester) async {
    await _pumpSidebar(tester);
    final expandido = _labelLeft(tester, 'Dashboard');
    expect(_labelOculto(tester, 'Dashboard'), isFalse);

    await tester.tap(find.byKey(const Key('sidebar_toggle_button')));
    await tester.pump();
    await tester.pump(AppMotion.base ~/ 2);

    final medio = _labelLeft(tester, 'Dashboard');

    await tester.pumpAndSettle();
    final colapsado = _labelLeft(tester, 'Dashboard');
    expect(_labelOculto(tester, 'Dashboard'), isTrue);

    // A mitad de camino el label TIENE que estar entre su lugar y su destino.
    // Si saltara al final en un frame, acá ya estaría en `colapsado` — que es
    // exactamente el salto que este cambio vino a sacar.
    //
    // La cota de arriba es el destino y NO el borde de los 72px: el recorrido
    // es 54→94, así que su punto medio cae en ~74 y ya pasó el borde estando
    // todavía en viaje. Medir contra el borde haría fallar una animación sana.
    expect(medio, greaterThan(expandido));
    expect(medio, lessThan(colapsado));
  });

  testWidgets('el label queda centrado con el ícono de su fila',
      (tester) async {
    await _pumpSidebar(tester);

    // Candado contra el bug que rompió el gate visual: darle `top`/`bottom` al
    // `AnimatedPositioned` del label lo estira a la altura de la fila y cambia
    // quién lo centra —el `Row` en vez del `Stack`—. El centro teórico es el
    // mismo; el redondeo no. Corrió cada label 1px y movió 374px en los cuatro
    // goldens, que es justo el tamaño de error que nadie ve revisando el diff.
    final label = tester.getRect(_primerItemLabel().first);
    final icono = tester.getRect(_primerItemIcono());
    expect(label.center.dy, closeTo(icono.center.dy, 0.5));

    // Y el label tiene que quedar metido hacia adentro lo MISMO que el ícono,
    // que es donde lo dejaba `right: 0` antes de ser un ancho calculado.
    //
    // `_labelWidth` es aritmética a mano y por lo tanto se equivoca en
    // silencio: la primera versión se olvidó del `Border` del sidebar, quedó
    // 1px más ancha, y ese píxel corrió dónde ellipsiza cada texto. No rompió
    // ningún test — sólo los cuatro goldens, y recién en CI.
    //
    // Se compara simetría y no un número: cualquier constante que se copie acá
    // (el margen de 8, el padding de 14, el borde) puede driftear del lib y
    // dejar de proteger nada.
    final fila =
        tester.getRect(find.byKey(ValueKey(sidebarRegistry.first.route)));
    expect(fila.right - label.right, closeTo(icono.left - fila.left, 0.5));
  });

  testWidgets('el ícono viaja al centro, no salta', (tester) async {
    await _pumpSidebar(tester);
    final expandido = tester.getCenter(_primerItemIcono()).dx;

    await tester.tap(find.byKey(const Key('sidebar_toggle_button')));
    await tester.pump();
    await tester.pump(AppMotion.base ~/ 2);
    final medio = tester.getCenter(_primerItemIcono()).dx;

    await tester.pumpAndSettle();
    final colapsado = tester.getCenter(_primerItemIcono()).dx;

    // Colapsado el ícono queda centrado en los 72px, así que se movió; y a
    // mitad de camino está ENTRE los dos, no ya en el destino.
    expect(colapsado, isNot(closeTo(expandido, 0.5)));
    expect(medio, isNot(closeTo(colapsado, 0.5)));
  });

  testWidgets('con reduce-motion no hay tramo intermedio', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);

    await _pumpSidebar(tester);
    await tester.tap(find.byKey(const Key('sidebar_toggle_button')));
    await tester.pump();

    // Un solo frame y ya está en el final: `resolve` devuelve Duration.zero.
    expect(_labelOculto(tester, 'Dashboard'), isTrue);
  });

  testWidgets('expandido el Tooltip existe pero está APAGADO', (tester) async {
    // Este test decía `find.byTooltip('Dashboard'), findsNothing` y pasaba —
    // porque expandido el mensaje era `''`, así que no había ningún Tooltip
    // con ESE mensaje. Y mientras tanto la burbuja vacía se dibujaba igual.
    //
    // O sea: el test verificaba el MECANISMO (qué string tenía el mensaje) en
    // vez de la conducta (si aparece algo en pantalla), y por eso el cuadrado
    // negro llegó a producción con la suite en verde. Ahora el mensaje es
    // siempre el label —quien apaga es `TooltipVisibility`— y lo que se afirma
    // es que no aparece NADA al hoverear, arriba en este mismo archivo.
    await _pumpSidebar(tester);

    expect(find.text('Dashboard'), findsOneWidget);
    // El widget está —tiene que estar, o cambiaría la forma del árbol y el
    // label volvería a saltar al colapsar— y lleva su mensaje real.
    expect(find.byTooltip('Dashboard'), findsOneWidget);

    final visibility = tester.widget<TooltipVisibility>(
      find
          .ancestor(
            of: find.byTooltip('Dashboard'),
            matching: find.byType(TooltipVisibility),
          )
          .first,
    );
    expect(visibility.visible, isFalse, reason: 'expandido no se dispara');
  });

  // ---------------------------------------------------------------------------
  // Accesibilidad — el lector no dice el label dos veces (hallazgo H)
  // ---------------------------------------------------------------------------
  group('CoachHubSidebar — semántica del item', () {
    // El árbol de semántica de producción devolvía «Dashboard Dashboard»,
    // «Alumnos Alumnos», «Solicitudes Solicitudes» — cada item del menú leído
    // dos veces por el lector de pantalla.
    //
    // El item ya se nombra a sí mismo con un `Semantics(label:)` afuera, en
    // los DOS estados (el comentario del código lo dice así). Pero el `Text`
    // visible de adentro estaba envuelto en `ExcludeSemantics(excluding:
    // collapsed)`: sólo se callaba con el sidebar COLAPSADO. Expandido
    // aportaba su propio label, y el `MergeSemantics` de arriba los pegaba.
    testWidgets('expandido, el label se anuncia UNA sola vez', (tester) async {
      final handle = tester.ensureSemantics();

      await _pumpSidebar(tester);

      final nodo = tester.getSemantics(
        find
            .ancestor(
              of: find.text('Dashboard'),
              matching: find.byType(MergeSemantics),
            )
            .last,
      );

      expect(
        nodo.label,
        'Dashboard',
        reason: 'el lector lo decía dos veces: «${nodo.label}»',
      );

      handle.dispose();
    });
  });
}

/// Igual que [_pumpSidebar] pero con `itemsOverride`, para los casos que
/// necesitan un `badgeProvider` fake.
Future<void> _pumpSidebarWithItems(
  WidgetTester tester, {
  required List<SidebarItem> items,
  Map<String, Object> prefs = const {},
  String initial = '/dashboard',
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final sp = await SharedPreferences.getInstance();

  final router = GoRouter(
    initialLocation: initial,
    routes: [
      ShellRoute(
        builder: (ctx, state, child) => Scaffold(
          body: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CoachHubSidebar(itemsOverride: items),
              Expanded(child: NavigatorSemanticsBoundary(child: child)),
            ],
          ),
        ),
        routes: [
          for (final p in {...items.map((i) => i.route), initial})
            GoRoute(path: p, builder: (_, __) => Text('page:$p')),
        ],
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWith((ref) => Future.value(sp)),
      ],
      child: MaterialApp.router(theme: AppTheme.dark(), routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}
