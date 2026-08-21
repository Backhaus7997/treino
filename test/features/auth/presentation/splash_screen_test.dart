import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/features/auth/application/auth_notifier.dart';
import 'package:treino/features/auth/application/auth_providers.dart';
import 'package:treino/features/auth/presentation/splash_screen.dart';
import 'package:treino/features/auth/presentation/widgets/treino_logo.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';
import 'package:treino/l10n/app_l10n.dart';

class MockUser extends Mock implements User {}

class _TestAuthNotifier extends AuthNotifier {
  _TestAuthNotifier({this.initialUser});
  final User? initialUser;

  @override
  Future<User?> build() async => initialUser;
}

GoRouter _makeRouter(Widget splash) => GoRouter(
      initialLocation: '/splash',
      routes: [
        GoRoute(path: '/splash', builder: (_, __) => splash),
        GoRoute(
          path: '/welcome',
          builder: (_, __) => const Scaffold(body: Text('WELCOME')),
        ),
        GoRoute(
          path: '/home',
          builder: (_, __) => const Scaffold(body: Text('HOME')),
        ),
      ],
    );

/// Perfil ya completo (displayName seteado). Desde issue #499 el splash espera
/// TAMBIÉN al perfil antes de mandar a /home, así que estos tests tienen que
/// proveerlo — si no, el provider real iría a Firestore.
UserProfile _completeProfile() => UserProfile(
      uid: 'test-uid',
      email: 'test@example.com',
      displayName: 'tincho',
      role: UserRole.athlete,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

Widget _buildApp({required _TestAuthNotifier notifier}) {
  const screen = SplashScreen();
  final router = _makeRouter(screen);
  return ProviderScope(
    overrides: [
      authNotifierProvider.overrideWith(() => notifier),
      userProfileProvider.overrideWith(
        (ref) => Stream<UserProfile?>.value(_completeProfile()),
      ),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
    ),
  );
}

void main() {
  // ---------------------------------------------------------------------------
  // Renders the brand visual on the first frame (while auth is still loading).
  // ---------------------------------------------------------------------------
  testWidgets('renders TreinoLogo and brand headline on first frame',
      (tester) async {
    final notifier = _TestAuthNotifier();

    await tester.pumpWidget(_buildApp(notifier: notifier));
    await tester.pump(); // first frame — auth still loading, splash visible

    expect(find.byType(TreinoLogo), findsOneWidget);
    // Brand headline lives in a RichText with TextSpans — extract plain text.
    final headlineText = tester
        .widgetList<RichText>(find.byType(RichText))
        .map((rt) => rt.text.toPlainText())
        .join(' ');
    // Keyed off l10n, not literal copy: splash and welcome now read the brand
    // headline from the same keys, so a copy change can't desync them.
    final l10n = AppL10n.of(tester.element(find.byType(TreinoLogo)));
    expect(headlineText, contains(l10n.authBrandHeadline1Light.trim()));
    expect(headlineText, contains(l10n.authBrandHeadline2Bold));

    await tester.pumpAndSettle();
  });

  // ---------------------------------------------------------------------------
  // Anonymous user → /welcome as soon as auth resolves. The old 1500ms minimum
  // delay was an accidental placeholder (audit Q8) — navigation must NOT wait
  // for it, so we advance only 100ms (far below 1500ms) and assert we already
  // left the splash.
  // ---------------------------------------------------------------------------
  testWidgets('anonymous user navigates to /welcome without artificial delay',
      (tester) async {
    final notifier = _TestAuthNotifier(initialUser: null);

    await tester.pumpWidget(_buildApp(notifier: notifier));
    await tester.pump(); // first frame
    await tester.pump(const Duration(milliseconds: 100)); // well below 1500ms
    await tester.pump(); // reflect the navigation frame

    expect(find.text('WELCOME'), findsOneWidget);
  });

  // ---------------------------------------------------------------------------
  // Authenticated user → /home as soon as auth resolves, no artificial delay.
  // ---------------------------------------------------------------------------
  testWidgets('authenticated user navigates to /home without artificial delay',
      (tester) async {
    final mockUser = MockUser();
    when(() => mockUser.emailVerified).thenReturn(true);
    final notifier = _TestAuthNotifier(initialUser: mockUser);

    await tester.pumpWidget(_buildApp(notifier: notifier));
    await tester.pump(); // first frame
    await tester.pump(const Duration(milliseconds: 100)); // well below 1500ms
    await tester.pump(); // reflect the navigation frame

    expect(find.text('HOME'), findsOneWidget);
  });

  // ---------------------------------------------------------------------------
  // QA H6: perfil cuyo stream NUNCA emite (snapshot cache-only filtrado + sin
  // red). Sin el `.timeout` el await no completaba nunca y el splash quedaba
  // con spinner para siempre. Ahora, a los 8s, muestra Reintentar y NO navega.
  // ---------------------------------------------------------------------------
  testWidgets(
      'perfil que nunca resuelve → a los 8s muestra Reintentar, no HOME',
      (tester) async {
    final mockUser = MockUser();
    when(() => mockUser.emailVerified).thenReturn(true);
    final notifier = _TestAuthNotifier(initialUser: mockUser);

    // Stream que queda abierto y nunca emite → userProfileProvider.future
    // nunca completa → dispara el timeout.
    final controller = StreamController<UserProfile?>();
    addTearDown(controller.close);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        authNotifierProvider.overrideWith(() => notifier),
        userProfileProvider.overrideWith((ref) => controller.stream),
      ],
      child: MaterialApp.router(
        routerConfig: _makeRouter(const SplashScreen()),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        locale: const Locale('es', 'AR'),
      ),
    ));
    await tester.pump(); // primer frame
    await tester.pump(const Duration(milliseconds: 100)); // auth resuelve

    // Antes del timeout: sigue en el splash con spinner, sin Reintentar.
    expect(find.text('HOME'), findsNothing);
    expect(find.text('Reintentar'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    // Avanzar más allá de los 8s del timeout.
    await tester.pump(const Duration(seconds: 9));
    await tester.pump();

    expect(find.text('Reintentar'), findsOneWidget);
    expect(find.text('HOME'), findsNothing,
        reason: 'un perfil que nunca emite no debe caer en /home con el gate '
            'en loading perpetuo');
  });
}
