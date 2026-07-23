import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/app/theme/tokens/components/coach_hub_layout_tokens.dart';
import 'package:treino/core/persistence/shared_prefs_provider.dart';
import 'package:treino/core/widgets/motion/treino_fade_slide_in.dart';
import 'package:treino/features/coach_hub/application/sidebar_collapsed_provider.dart';
import 'package:treino/features/coach_hub/presentation/shell/coach_hub_scaffold.dart';
import 'package:treino/features/coach_hub/presentation/shell/coach_hub_sidebar.dart';
import 'package:treino/features/coach_hub/presentation/shell/coach_hub_top_bar.dart';
import 'package:treino/features/coach_hub/presentation/shell/mobile_banner.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/domain/user_profile.dart';

/// Monta el `CoachHubScaffold` dentro de un `ShellRoute`, con el `child`
/// provisto por la ruta activa (como en producción, ADR-CHW-008). `prefs`
/// siembra `shared_preferences` (eg. estado colapsado guardado).
Future<void> _pumpScaffold(
  WidgetTester tester, {
  Map<String, Object> prefs = const {},
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final sp = await SharedPreferences.getInstance();

  final router = GoRouter(
    initialLocation: '/dashboard',
    routes: [
      ShellRoute(
        pageBuilder: (ctx, state, child) =>
            NoTransitionPage(child: CoachHubScaffold(child: child)),
        routes: [
          GoRoute(
            path: '/dashboard',
            builder: (_, __) => const Text('CONTENT_SLOT'),
          ),
        ],
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWith((ref) => Future.value(sp)),
        userProfileProvider
            .overrideWith((ref) => Stream<UserProfile?>.value(null)),
      ],
      child: MaterialApp.router(theme: AppTheme.dark(), routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

/// Setea el viewport lógico (devicePixelRatio 1.0) y lo resetea en teardown.
void _setWidth(WidgetTester tester, double width) {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

double _sidebarWidth(WidgetTester tester) =>
    tester.getSize(find.byKey(const Key('coach_hub_sidebar_container'))).width;

void main() {
  testWidgets('renderiza sidebar + top bar + slot de contenido [SCENARIO-748]',
      (tester) async {
    await _pumpScaffold(tester);

    expect(find.byType(CoachHubSidebar), findsOneWidget);
    expect(find.byType(CoachHubTopBar), findsOneWidget);
    expect(find.text('CONTENT_SLOT'), findsOneWidget);
  });

  testWidgets('usa palette.bg como fondo, sin HEX literal [SCENARIO-749]',
      (tester) async {
    await _pumpScaffold(tester);

    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.backgroundColor, AppPalette.mintMagenta.bg);
  });

  testWidgets('existe exactamente un Scaffold en el shell', (tester) async {
    await _pumpScaffold(tester);
    expect(find.byType(Scaffold), findsOneWidget);
  });

  testWidgets(
      'usa CoachHubLayoutTokens.contentMaxWidth (1240) — REQ-SH-008/020',
      (tester) async {
    await _pumpScaffold(tester);
    final contentMaxWidth = tester.widget<ConstrainedBox>(
      find.byWidgetPredicate(
        (w) =>
            w is ConstrainedBox &&
            w.constraints.maxWidth == CoachHubLayoutTokens.contentMaxWidth,
      ),
    );
    expect(contentMaxWidth.constraints.maxWidth, 1240);
  });

  testWidgets('entrada del contenido usa TreinoFadeSlideIn — REQ-SH-010',
      (tester) async {
    await _pumpScaffold(tester);
    expect(find.byType(TreinoFadeSlideIn), findsWidgets);
  });

  group('guard responsivo (W1.3, ADR-CHW-004)', () {
    testWidgets('ancho 600 (mobile) → MobileBanner, sin sidebar [SCENARIO-762]',
        (tester) async {
      _setWidth(tester, 600);
      await _pumpScaffold(tester);

      expect(find.byType(MobileBanner), findsOneWidget);
      expect(find.byType(CoachHubSidebar), findsNothing);
      expect(find.byType(CoachHubTopBar), findsNothing);
    });

    testWidgets('ancho 900 (compact, banda tablet 768–1023) → sidebar a 72 px',
        (tester) async {
      _setWidth(tester, 900);
      await _pumpScaffold(tester);

      expect(find.byType(CoachHubSidebar), findsOneWidget);
      expect(_sidebarWidth(tester), 72);
    });

    testWidgets(
        'ancho 1100 (compact) → sidebar forzado a 72 px y toggle deshabilitado '
        '[SCENARIO-763]', (tester) async {
      _setWidth(tester, 1100);
      await _pumpScaffold(
          tester); // prefs vacías → provider = false (expandido)

      expect(find.byType(CoachHubSidebar), findsOneWidget);
      expect(_sidebarWidth(tester), 72); // forzado pese a provider=false
      final toggle = tester.widget<IconButton>(
        find.byKey(const Key('sidebar_toggle_button')),
      );
      expect(toggle.onPressed, isNull);
    });

    testWidgets(
        'ancho 1400 (desktop) → sidebar respeta provider (240 expandido) '
        '[SCENARIO-762]', (tester) async {
      _setWidth(tester, 1400);
      await _pumpScaffold(tester); // provider = false → expandido

      expect(_sidebarWidth(tester), CoachHubLayoutTokens.sidebarExpandedWidth);
      expect(_sidebarWidth(tester), 240);
    });

    testWidgets(
        'ancho 1400 (desktop) + colapsado guardado → sidebar 72 (respeta '
        'provider, NO forzado)', (tester) async {
      _setWidth(tester, 1400);
      await _pumpScaffold(
        tester,
        prefs: const {'coach_hub.sidebar.collapsed': true},
      );

      expect(_sidebarWidth(tester), 72);
    });

    testWidgets(
        'compact NO escribe sidebarCollapsedProvider — preserva el estado '
        'guardado al volver a desktop (ADR-CHW-004)', (tester) async {
      _setWidth(tester, 1100); // compact → force-collapse
      SharedPreferences.setMockInitialValues(
          {}); // guardado = false (expandido)
      final sp = await SharedPreferences.getInstance();
      final container = ProviderContainer(overrides: [
        sharedPreferencesProvider.overrideWith((ref) => Future.value(sp)),
        userProfileProvider
            .overrideWith((ref) => Stream<UserProfile?>.value(null)),
      ]);
      addTearDown(container.dispose);
      await container.read(sharedPreferencesProvider.future);

      final router = GoRouter(
        initialLocation: '/dashboard',
        routes: [
          ShellRoute(
            pageBuilder: (ctx, state, child) =>
                NoTransitionPage(child: CoachHubScaffold(child: child)),
            routes: [
              GoRoute(
                path: '/dashboard',
                builder: (_, __) => const Text('CONTENT_SLOT'),
              ),
            ],
          ),
        ],
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child:
              MaterialApp.router(theme: AppTheme.dark(), routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      // Se ve colapsado (forzado por el viewport compact)...
      expect(_sidebarWidth(tester), 72);
      // ...pero el provider NUNCA fue escrito: sigue false. Ése es el mecanismo
      // que garantiza que al volver a desktop el sidebar se restaure a
      // expandido — el override de compact es solo local (ADR-CHW-004).
      expect(container.read(sidebarCollapsedProvider), isFalse);
    });
  });
}
