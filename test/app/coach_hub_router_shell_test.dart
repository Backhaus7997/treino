// Shell invariant test for the Coach Hub router (W1.2.5, REQ-CHW-ROUTER-002,
// REQ-CHW-QA-002).
//
// Asserts the structural contract of ADR-CHW-001: public routes (`/login`,
// `/not-allowed`) are top-level siblings that DO NOT render `CoachHubScaffold`,
// while signed-in routes (`/dashboard`) live inside the `ShellRoute` and DO.
//
// Unlike `coach_hub_router_redirect_test.dart` (which tests the pure redirect
// function), this pumps the real `buildCoachHubRouter` to verify the wiring.
// The router hardcodes `initialLocation: '/dashboard'`, so we warm the auth +
// profile providers before pumping and let the redirect route each role to its
// destination (a dummy `refreshListenable` would not re-fire the redirect once
// providers resolve later).

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:treino/app/coach_hub_router.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/auth/application/auth_notifier.dart';
import 'package:treino/features/auth/application/auth_providers.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart';
import 'package:treino/features/coach/domain/trainer_link.dart';
import 'package:treino/core/persistence/shared_prefs_provider.dart';
import 'package:treino/features/coach_hub/application/sidebar_collapsed_provider.dart';
import 'package:treino/features/coach_hub/presentation/sections/dashboard/coach_hub_dashboard_screen.dart';
import 'package:treino/features/coach_hub/presentation/coach_hub_login_screen.dart';
import 'package:treino/features/coach_hub/presentation/coach_hub_not_allowed_screen.dart';
import 'package:treino/features/coach_hub/presentation/shell/coach_hub_scaffold.dart';
import 'package:treino/features/coach_hub/presentation/shell/proximamente_screen.dart';
import 'package:treino/l10n/app_l10n.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';

class _MockUser extends Mock implements User {}

class _StubAuthNotifier extends AuthNotifier {
  _StubAuthNotifier(this._fixedState);
  final AsyncValue<User?> _fixedState;

  @override
  Future<User?> build() async {
    state = _fixedState;
    return _fixedState.valueOrNull;
  }
}

UserProfile _trainerProfile() => UserProfile(
      uid: 'test-uid',
      email: 'trainer@example.com',
      displayName: 'Mateo',
      role: UserRole.trainer,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

UserProfile _athleteProfile() => UserProfile(
      uid: 'test-uid',
      email: 'athlete@example.com',
      displayName: 'Tincho',
      role: UserRole.athlete,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

/// Builds the shared container, warms auth + profile so the redirect resolves
/// on first evaluation, pumps the real router, and settles. Returns the
/// [GoRouter] so a test can navigate to a deeper route (e.g. a placeholder).
Future<GoRouter> _pumpRouter(
  WidgetTester tester, {
  required Override authOverride,
  Override? profileOverride,
}) async {
  // Coach Hub es un layout de escritorio (min 1024px). En el surface default
  // de 800x600 el sidebar (264px) deja muy poco ancho y el dashboard real
  // desborda. Pumpeamos a un tamaño desktop realista.
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  SharedPreferences.setMockInitialValues({});
  final sp = await SharedPreferences.getInstance();

  final container = ProviderContainer(overrides: [
    authOverride,
    profileOverride ??
        userProfileProvider
            .overrideWith((ref) => Stream<UserProfile?>.value(null)),
    sharedPreferencesProvider.overrideWith((ref) => Future.value(sp)),
    trainerLinksStreamProvider
        .overrideWith((ref) => Stream.value(const <TrainerLink>[])),
  ]);
  addTearDown(container.dispose);

  // Warm the providers the redirect reads — without this they are AsyncLoading
  // at first evaluation and the redirect defensively returns null (stay).
  await tester.runAsync(() async {
    await container.read(authNotifierProvider.future).catchError(
          (_) => null,
        );
    await container.read(userProfileProvider.future).catchError(
          (_) => null,
        );
  });

  final refresh = ValueNotifier<int>(0);
  addTearDown(refresh.dispose);
  final router = buildCoachHubRouter(
    refreshListenable: refresh,
    read: container.read,
  );

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        theme: AppTheme.dark(),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

void main() {
  group('Coach Hub router shell invariant (ADR-CHW-001)', () {
    testWidgets(
      'anonymous → /login does NOT render CoachHubScaffold [SCENARIO-758]',
      (tester) async {
        await _pumpRouter(
          tester,
          authOverride: authNotifierProvider.overrideWith(
            () => _StubAuthNotifier(const AsyncData(null)),
          ),
        );

        expect(find.byType(CoachHubScaffold), findsNothing);
        expect(find.byType(CoachHubLoginScreen), findsOneWidget);
      },
    );

    testWidgets(
      'athlete → /not-allowed does NOT render CoachHubScaffold [SCENARIO-759]',
      (tester) async {
        final user = _MockUser();
        await _pumpRouter(
          tester,
          authOverride: authNotifierProvider.overrideWith(
            () => _StubAuthNotifier(AsyncData(user)),
          ),
          profileOverride: userProfileProvider.overrideWith(
            (ref) => Stream<UserProfile?>.value(_athleteProfile()),
          ),
        );

        expect(find.byType(CoachHubScaffold), findsNothing);
        expect(find.byType(CoachHubNotAllowedScreen), findsOneWidget);
      },
    );

    testWidgets(
      'trainer → /dashboard renders exactly one CoachHubScaffold [SCENARIO-770]',
      (tester) async {
        final user = _MockUser();
        await _pumpRouter(
          tester,
          authOverride: authNotifierProvider.overrideWith(
            () => _StubAuthNotifier(AsyncData(user)),
          ),
          profileOverride: userProfileProvider.overrideWith(
            (ref) => Stream<UserProfile?>.value(_trainerProfile()),
          ),
        );

        expect(find.byType(CoachHubScaffold), findsOneWidget);
        expect(find.byType(CoachHubDashboardScreen), findsOneWidget);
      },
    );

    testWidgets(
      'trainer → placeholder route renders ProximamenteScreen inside the shell '
      '[SCENARIO-753]',
      (tester) async {
        final user = _MockUser();
        final router = await _pumpRouter(
          tester,
          authOverride: authNotifierProvider.overrideWith(
            () => _StubAuthNotifier(AsyncData(user)),
          ),
          profileOverride: userProfileProvider.overrideWith(
            (ref) => Stream<UserProfile?>.value(_trainerProfile()),
          ),
        );

        router.go('/nutricion');
        await tester.pumpAndSettle();

        // Placeholder renders WITHIN the shell (sidebar stays visible).
        expect(find.byType(CoachHubScaffold), findsOneWidget);
        expect(find.byType(ProximamenteScreen), findsOneWidget);
        expect(find.text('Próximamente.'), findsOneWidget);
      },
    );
  });
}
