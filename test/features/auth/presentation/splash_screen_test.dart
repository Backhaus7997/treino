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

Widget _buildApp({required _TestAuthNotifier notifier}) {
  const screen = SplashScreen();
  final router = _makeRouter(screen);
  return ProviderScope(
    overrides: [authNotifierProvider.overrideWith(() => notifier)],
    child: MaterialApp.router(routerConfig: router),
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
    expect(headlineText, contains('MOVÉS'));
    expect(headlineText, contains('EL RESTO.'));

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
}
