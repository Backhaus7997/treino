// W1.4.6 — the dashboard now lives INSIDE the shell (ADR-CHW-005).
//
// Asserts the contract of W1.4: pumped at /dashboard via the real router, the
// dashboard has NO Scaffold of its own (the shell provides the single one) and
// NO brand header, while its content (the upload-plan CTA) still renders.
//
// Harness mirrors coach_hub_router_shell_test.dart: warm auth + profile so the
// redirect resolves on first evaluation, share one container via
// UncontrolledProviderScope, pump at a desktop width.

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:treino/app/coach_hub_router.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/l10n/app_l10n.dart';
import 'package:treino/features/auth/application/auth_notifier.dart';
import 'package:treino/features/auth/application/auth_providers.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart';
import 'package:treino/features/coach/domain/trainer_link.dart';
import 'package:treino/core/persistence/shared_prefs_provider.dart';
import 'package:treino/features/coach_hub/application/sidebar_collapsed_provider.dart';
import 'package:treino/features/coach_hub/presentation/sections/dashboard/coach_hub_dashboard_screen.dart';
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

Future<void> _pumpDashboardInShell(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1400, 900); // desktop → shell renders
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  SharedPreferences.setMockInitialValues({});
  final sp = await SharedPreferences.getInstance();
  final user = _MockUser();

  final container = ProviderContainer(overrides: [
    authNotifierProvider.overrideWith(() => _StubAuthNotifier(AsyncData(user))),
    userProfileProvider
        .overrideWith((ref) => Stream<UserProfile?>.value(_trainerProfile())),
    trainerLinksStreamProvider
        .overrideWith((ref) => Stream.value(const <TrainerLink>[])),
    sharedPreferencesProvider.overrideWith((ref) => Future.value(sp)),
  ]);
  addTearDown(container.dispose);

  await tester.runAsync(() async {
    await container.read(authNotifierProvider.future).catchError((_) => null);
    await container.read(userProfileProvider.future).catchError((_) => null);
  });

  final refresh = ValueNotifier<int>(0);
  addTearDown(refresh.dispose);
  final router =
      buildCoachHubRouter(refreshListenable: refresh, read: container.read);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        theme: AppTheme.dark(),
        routerConfig: router,
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('Dashboard dentro del shell (W1.4, ADR-CHW-005)', () {
    testWidgets('exactamente un Scaffold — el del shell [SCENARIO-769]',
        (tester) async {
      await _pumpDashboardInShell(tester);
      expect(find.byType(CoachHubDashboardScreen), findsOneWidget);
      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('el header de marca ya no se renderiza [SCENARIO-765]',
        (tester) async {
      await _pumpDashboardInShell(tester);
      // Guard contra pase vacuo: el dashboard tiene que estar montado.
      expect(find.byType(CoachHubDashboardScreen), findsOneWidget);
      // Scopeado al subárbol del dashboard: 'BIENVENIDO'/'TREINO COACH HUB' no
      // son únicos (login/upload-plan los usan), así el assert falla por la
      // razón correcta si un refactor futuro reintroduce el header acá.
      expect(
        find.descendant(
          of: find.byType(CoachHubDashboardScreen),
          matching: find.text('TREINO COACH HUB'),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byType(CoachHubDashboardScreen),
          matching: find.textContaining('BIENVENIDO'),
        ),
        findsNothing,
      );
    });

    testWidgets('el CTA de importar plan sigue presente [SCENARIO-764]',
        (tester) async {
      await _pumpDashboardInShell(tester);
      expect(find.text('IMPORTAR PLAN DESDE EXCEL'), findsOneWidget);
    });
  });
}
