import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:treino/features/auth/presentation/welcome_screen.dart';
import 'package:treino/features/auth/presentation/widgets/auth_pill_button.dart';
import 'package:treino/features/auth/presentation/widgets/auth_secondary_button.dart';
import 'package:treino/features/auth/presentation/widgets/treino_logo.dart';

GoRouter _makeRouter(Widget home) => GoRouter(
      initialLocation: '/welcome',
      routes: [
        GoRoute(path: '/welcome', builder: (_, __) => home),
        GoRoute(
          path: '/register',
          builder: (_, __) => const Scaffold(body: Text('REGISTER')),
        ),
        GoRoute(
          path: '/login',
          builder: (_, __) => const Scaffold(body: Text('LOGIN')),
        ),
      ],
    );

Widget _buildApp() {
  const screen = WelcomeScreen();
  final router = _makeRouter(screen);
  return ProviderScope(child: MaterialApp.router(routerConfig: router));
}

void main() {
  // ---------------------------------------------------------------------------
  // B03: renders eyebrow, logo, headline, body, CTA
  // ---------------------------------------------------------------------------
  testWidgets('renders eyebrow text', (tester) async {
    await tester.pumpWidget(_buildApp());
    await tester.pumpAndSettle();

    expect(find.textContaining('ENTRENAMIENTO'), findsOneWidget);
  });

  testWidgets('renders TreinoLogo', (tester) async {
    await tester.pumpWidget(_buildApp());
    await tester.pumpAndSettle();

    expect(find.byType(TreinoLogo), findsOneWidget);
  });

  testWidgets('renders headline parts', (tester) async {
    await tester.pumpWidget(_buildApp());
    await tester.pumpAndSettle();

    expect(find.textContaining('MOVÉS'), findsOneWidget);
    expect(find.textContaining('NOSOTROS'), findsOneWidget);
  });

  testWidgets('renders body text', (tester) async {
    await tester.pumpWidget(_buildApp());
    await tester.pumpAndSettle();

    expect(find.textContaining('Cargá tu rutina'), findsOneWidget);
  });

  // ---------------------------------------------------------------------------
  // B03: "EMPEZAR" CTA navigates to /register
  // ---------------------------------------------------------------------------
  testWidgets('EMPEZAR CTA navigates to /register', (tester) async {
    await tester.pumpWidget(_buildApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byType(AuthPillButton));
    await tester.pumpAndSettle();

    expect(find.text('REGISTER'), findsOneWidget);
  });

  // ---------------------------------------------------------------------------
  // B03: Google and Apple buttons are disabled with tooltip "Próximamente"
  // ---------------------------------------------------------------------------
  testWidgets('Google and Apple AuthSecondaryButtons are present',
      (tester) async {
    await tester.pumpWidget(_buildApp());
    await tester.pumpAndSettle();

    expect(find.byType(AuthSecondaryButton), findsNWidgets(2));
  });

  testWidgets('Google and Apple buttons are disabled (onPressed null)',
      (tester) async {
    await tester.pumpWidget(_buildApp());
    await tester.pumpAndSettle();

    final buttons =
        tester.widgetList<OutlinedButton>(find.byType(OutlinedButton)).toList();
    // Both social buttons should be disabled
    expect(buttons.every((b) => b.onPressed == null), isTrue);
  });

  // ---------------------------------------------------------------------------
  // B03: "Iniciar sesión" link navigates to /login
  // ---------------------------------------------------------------------------
  testWidgets('"Iniciar sesión" link navigates to /login', (tester) async {
    await tester.pumpWidget(_buildApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Iniciar sesión'));
    await tester.pumpAndSettle();

    expect(find.text('LOGIN'), findsOneWidget);
  });
}
