// Tests for CoachHubTopBar (REQ-SH-007, SCENARIO-760).
//
// Pumped inside a GoRouter + ProviderScope for parity with how the real shell
// mounts it (userProfileProvider drives the avatar initial, GoRouterState
// drives the section title).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/app/theme/theme_mode_provider.dart';
import 'package:treino/core/persistence/shared_prefs_provider.dart';
import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/features/coach_hub/presentation/shell/coach_hub_top_bar.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';

UserProfile _profile(String displayName) => UserProfile(
      uid: 'trainer-1',
      email: 'trainer@example.com',
      displayName: displayName,
      role: UserRole.trainer,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

/// Devuelve el [ProviderContainer] usado, por si el test necesita leer/
/// escribir providers directamente (eg. `themeModeProvider`).
Future<ProviderContainer> _pumpTopBar(
  WidgetTester tester, {
  UserProfile? profile,
  String initial = '/dashboard',
  ThemeData? theme,
}) async {
  tester.view.physicalSize = const Size(1400, 900); // desktop → toggle enabled
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  SharedPreferences.setMockInitialValues({});
  final sp = await SharedPreferences.getInstance();

  final container = ProviderContainer(overrides: [
    sharedPreferencesProvider.overrideWith((ref) => Future.value(sp)),
    userProfileProvider
        .overrideWith((ref) => Stream<UserProfile?>.value(profile)),
  ]);
  addTearDown(container.dispose);
  // themeModeProvider hace `.requireValue` sobre sharedPreferencesProvider
  // (ADR-LM-009: se asume resuelto antes de `runApp`) — en test hay que
  // esperar el future explícitamente antes del primer pump síncrono.
  await container.read(sharedPreferencesProvider.future);

  final router = GoRouter(
    initialLocation: initial,
    routes: [
      GoRoute(
        path: '/dashboard',
        builder: (_, __) => const Scaffold(body: CoachHubTopBar()),
      ),
      GoRoute(
        path: '/alumnos',
        builder: (_, __) => const Scaffold(body: CoachHubTopBar()),
      ),
    ],
  );

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        theme: theme ?? AppTheme.dark(),
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  group('CoachHubTopBar (REQ-SH-007)', () {
    testWidgets(
        'el toggle del sidebar ya NO vive en el top bar (se movió al '
        'footer del sidebar)', (tester) async {
      await _pumpTopBar(tester);
      expect(find.byTooltip('Contraer/expandir menú'), findsNothing);
      expect(find.byTooltip('Contraer menú'), findsNothing);
    });

    testWidgets('campana presente a la derecha (inerte)', (tester) async {
      await _pumpTopBar(tester);
      expect(find.byTooltip('Notificaciones'), findsOneWidget);
    });

    testWidgets('menú de usuario presente, con chevron junto al avatar',
        (tester) async {
      await _pumpTopBar(tester);
      expect(find.byType(PopupMenuButton<String>), findsOneWidget);
      expect(find.byIcon(TreinoIcon.chevronDown), findsOneWidget);
    });

    testWidgets('avatar muestra la inicial del displayName', (tester) async {
      await _pumpTopBar(tester, profile: _profile('Ana'));
      expect(find.text('A'), findsOneWidget);
    });

    testWidgets('avatar cae a "?" sin profile', (tester) async {
      await _pumpTopBar(tester); // profile null
      expect(find.text('?'), findsOneWidget);
    });

    testWidgets('al abrir el menú aparece "Salir"', (tester) async {
      await _pumpTopBar(tester, profile: _profile('Ana'));
      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      expect(find.text('Salir'), findsOneWidget);
    });

    testWidgets('título de sección Barlow Condensed 700 UPPERCASE en /dashboard',
        (tester) async {
      await _pumpTopBar(tester, initial: '/dashboard');
      expect(find.text('DASHBOARD'), findsOneWidget);
    });

    testWidgets('título de sección cambia con la ruta activa (/alumnos)',
        (tester) async {
      await _pumpTopBar(tester, initial: '/alumnos');
      expect(find.text('ALUMNOS'), findsOneWidget);
    });

    testWidgets('campo de búsqueda decorativo presente (placeholder, Fase 1)',
        (tester) async {
      await _pumpTopBar(tester);
      expect(
        find.text('Buscar alumnos, rutinas, plan...'),
        findsOneWidget,
      );
      expect(find.byIcon(TreinoIcon.search), findsOneWidget);
      // Decorativo: es un TextField deshabilitado, no navega ni filtra en Fase 1.
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.enabled, isFalse);
    });

    testWidgets(
        'menú de cuenta expone Sistema/Claro/Oscuro y escribe themeModeProvider '
        '(REQ-SH-007, ADR-SH-005)', (tester) async {
      final container = await _pumpTopBar(tester);

      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();

      expect(find.text('Sistema'), findsOneWidget);
      expect(find.text('Claro'), findsOneWidget);
      expect(find.text('Oscuro'), findsOneWidget);

      await tester.tap(find.text('Oscuro'));
      await tester.pumpAndSettle();

      expect(container.read(themeModeProvider), ThemeMode.dark);
    });

    testWidgets('smoke visual en tema claro (mintMagentaLight) — REQ-SH-011',
        (tester) async {
      await _pumpTopBar(tester, theme: AppTheme.light());
      expect(find.text('DASHBOARD'), findsOneWidget);
      expect(find.byType(PopupMenuButton<String>), findsOneWidget);
    });
  });
}
