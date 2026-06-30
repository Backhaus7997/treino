// Tests for CoachHubTopBar (W1.3.3, REQ-CHW-TOPBAR-001, SCENARIO-760).
//
// The top bar reads sidebarCollapsedProvider (gated by sharedPreferences) and
// userProfileProvider, and embeds CoachHubBreadcrumb (needs GoRouterState), so
// it is pumped inside a GoRouter + ProviderScope at a desktop width (toggle
// enabled).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/persistence/shared_prefs_provider.dart';
import 'package:treino/features/coach_hub/application/sidebar_collapsed_provider.dart';
import 'package:treino/features/coach_hub/presentation/shell/coach_hub_breadcrumb.dart';
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

Future<void> _pumpTopBar(WidgetTester tester, {UserProfile? profile}) async {
  tester.view.physicalSize = const Size(1400, 900); // desktop → toggle enabled
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  SharedPreferences.setMockInitialValues({});
  final sp = await SharedPreferences.getInstance();

  final router = GoRouter(
    initialLocation: '/dashboard',
    routes: [
      GoRoute(
        path: '/dashboard',
        builder: (_, __) => const Scaffold(body: CoachHubTopBar()),
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWith((ref) => Future.value(sp)),
        userProfileProvider
            .overrideWith((ref) => Stream<UserProfile?>.value(profile)),
      ],
      child: MaterialApp.router(theme: AppTheme.dark(), routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('CoachHubTopBar (REQ-CHW-TOPBAR-001)', () {
    testWidgets('toggle del sidebar presente y habilitado en desktop',
        (tester) async {
      await _pumpTopBar(tester);
      final toggle = find.ancestor(
        of: find.byTooltip('Contraer/expandir menú'),
        matching: find.byType(IconButton),
      );
      expect(toggle, findsOneWidget);
      expect(tester.widget<IconButton>(toggle).onPressed, isNotNull);
    });

    testWidgets('breadcrumb embebido', (tester) async {
      await _pumpTopBar(tester);
      expect(find.byType(CoachHubBreadcrumb), findsOneWidget);
    });

    testWidgets('campana presente a la derecha (inerte)', (tester) async {
      await _pumpTopBar(tester);
      expect(find.byTooltip('Notificaciones'), findsOneWidget);
    });

    testWidgets('menú de usuario presente', (tester) async {
      await _pumpTopBar(tester);
      expect(find.byType(PopupMenuButton<String>), findsOneWidget);
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
  });
}
