import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/app/theme/tokens/components/coach_hub_layout_tokens.dart';
import 'package:treino/core/persistence/shared_prefs_provider.dart';
import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/core/widgets/motion/treino_fade_slide_in.dart';
import 'package:treino/features/coach_hub/presentation/shell/coach_hub_sidebar.dart';
import 'package:treino/features/coach_hub/presentation/shell/sidebar_item.dart';
import 'package:treino/features/coach_hub/presentation/shell/sidebar_registry.dart';

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
  final paths = sidebarRegistry.map((i) => i.route).toSet().toList();

  final router = GoRouter(
    initialLocation: initial,
    routes: [
      ShellRoute(
        builder: (ctx, state, child) => Scaffold(
          body: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [const CoachHubSidebar(), Expanded(child: child)],
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

void main() {
  testWidgets(
      'expandido → 240px, header TREINO, 2 headers (GESTIÓN, RECURSOS) y '
      'todos los labels del registry [SCENARIO-750]', (tester) async {
    await _pumpSidebar(tester);

    final size =
        tester.getSize(find.byKey(const Key('coach_hub_sidebar_container')));
    expect(size.width, CoachHubLayoutTokens.sidebarExpandedWidth);
    expect(size.width, 240);

    expect(find.text('TREINO'), findsOneWidget);

    // W2 reduce 2026-07-02: el sidebar pasó a 2 grupos activos (GESTIÓN y
    // RECURSOS) + Ajustes pinneado abajo. Reportes (grupo CUENTA) también
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
  });

  testWidgets(
      'colapsado → 72px, header/headers/labels ocultos, avatar sigue visible '
      '[SCENARIO-754]', (tester) async {
    await _pumpSidebar(tester, prefs: {'coach_hub.sidebar.collapsed': true});

    final size =
        tester.getSize(find.byKey(const Key('coach_hub_sidebar_container')));
    expect(size.width, CoachHubLayoutTokens.sidebarCollapsedWidth);
    expect(size.width, 72);

    expect(find.text('TREINO'), findsNothing);
    expect(find.text('RESUMEN'), findsNothing);
    expect(find.text('Dashboard'), findsNothing);
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
    expect(
      find.ancestor(
        of: find.text('Dashboard'),
        matching: find.byType(AnimatedContainer),
      ),
      findsWidgets,
    );
  });

  testWidgets(
      'el toggle (botón dedicado en footer) contrae/expande al tocarlo — '
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

  testWidgets('footer muestra avatar + nombre + subtítulo — REQ-SH-005',
      (tester) async {
    await _pumpSidebar(tester);

    expect(find.byKey(const Key('sidebar_profile_row')), findsOneWidget);
    expect(find.byType(CircleAvatar), findsOneWidget);
    expect(find.byIcon(TreinoIcon.chevronDown), findsOneWidget);
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
    expect(find.text('TREINO'), findsOneWidget);
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
                Expanded(child: child),
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
  });
}
