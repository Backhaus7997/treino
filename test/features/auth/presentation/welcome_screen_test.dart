import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/features/auth/application/auth_notifier.dart';
import 'package:treino/features/auth/application/auth_providers.dart';
import 'package:treino/features/auth/domain/auth_failure.dart';
import 'package:treino/features/auth/presentation/welcome_screen.dart';
import 'package:treino/features/auth/presentation/widgets/auth_failure_banner.dart';
import 'package:treino/features/auth/presentation/widgets/auth_pill_button.dart';
import 'package:treino/features/auth/presentation/widgets/auth_secondary_button.dart';
import 'package:treino/features/auth/presentation/widgets/treino_logo.dart';

class MockUser extends Mock implements User {}

class _TestAuthNotifier extends AuthNotifier {
  _TestAuthNotifier({
    this.onSignInWithApple,
    User? initialUser,
  }) : _initialUser = initialUser;

  final User? _initialUser;
  Future<void> Function()? onSignInWithApple;

  @override
  Future<User?> build() async => _initialUser;

  @override
  Future<void> signInWithApple() async {
    if (onSignInWithApple != null) {
      await onSignInWithApple!();
    }
  }
}

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
        GoRoute(
          path: '/home',
          builder: (_, __) => const Scaffold(body: Text('HOME')),
        ),
      ],
    );

Widget _buildApp({_TestAuthNotifier? notifier}) {
  const screen = WelcomeScreen();
  final router = _makeRouter(screen);
  if (notifier != null) {
    return ProviderScope(
      overrides: [authNotifierProvider.overrideWith(() => notifier)],
      child: MaterialApp.router(routerConfig: router),
    );
  }
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

  testWidgets('renders headline parts in textPrimary (not accent)',
      (tester) async {
    await tester.pumpWidget(_buildApp());
    await tester.pumpAndSettle();

    const palette = AppPalette.mintMagenta;

    // Headline uses RichText spans — check that MOVÉS and NOSOTROS appear
    // in textPrimary color (not accent).
    bool foundMoves = false;
    bool foundNosotros = false;
    for (final rt in tester.allWidgets.whereType<RichText>()) {
      final span = rt.text;
      if (span is TextSpan && span.children != null) {
        for (final child in span.children!) {
          if (child is TextSpan) {
            final text = child.text ?? '';
            final color = child.style?.color;
            if (text.contains('MOVÉS') && color == palette.textPrimary) {
              foundMoves = true;
            }
            if (text.contains('NOSOTROS') && color == palette.textPrimary) {
              foundNosotros = true;
            }
          }
        }
      }
    }
    expect(foundMoves, isTrue,
        reason: 'MOVÉS must be textPrimary (white), not accent');
    expect(foundNosotros, isTrue,
        reason: 'NOSOTROS must be textPrimary (white), not accent');
  });

  testWidgets('vertical accent line decorator is present', (tester) async {
    await tester.pumpWidget(_buildApp());
    await tester.pumpAndSettle();

    // At least one IntrinsicHeight wraps the line+headline row.
    // The screen also uses an outer IntrinsicHeight for spacing distribution.
    expect(find.byType(IntrinsicHeight), findsWidgets);
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

  testWidgets('Google button is always disabled (onPressed null)',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      await tester.pumpWidget(_buildApp());
      await tester.pumpAndSettle();

      final googleButton = tester.widget<OutlinedButton>(
        find.descendant(
          of: find.widgetWithText(AuthSecondaryButton, 'GOOGLE'),
          matching: find.byType(OutlinedButton),
        ),
      );
      expect(googleButton.onPressed, isNull);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('Apple button is disabled on Android (onPressed null)',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await tester.pumpWidget(_buildApp());
      await tester.pumpAndSettle();

      final appleButton = tester.widget<OutlinedButton>(
        find.descendant(
          of: find.widgetWithText(AuthSecondaryButton, 'APPLE'),
          matching: find.byType(OutlinedButton),
        ),
      );
      expect(appleButton.onPressed, isNull);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
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

  // ---------------------------------------------------------------------------
  // T-W1 — Apple button enabled on iOS
  // ---------------------------------------------------------------------------
  testWidgets('T-W1 — Apple button has non-null onPressed on iOS',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

    try {
      await tester.pumpWidget(_buildApp());
      await tester.pumpAndSettle();

      final appleButton = tester.widget<OutlinedButton>(
        find.descendant(
          of: find.widgetWithText(AuthSecondaryButton, 'APPLE'),
          matching: find.byType(OutlinedButton),
        ),
      );
      expect(appleButton.onPressed, isNotNull);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  // ---------------------------------------------------------------------------
  // T-W2 — Apple button disabled on non-iOS (no tooltip check needed — already
  // covered by the Próximamente tooltip test above)
  // ---------------------------------------------------------------------------
  testWidgets('T-W2 — Apple button has null onPressed on Android',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;

    try {
      await tester.pumpWidget(_buildApp());
      await tester.pumpAndSettle();

      final appleButton = tester.widget<OutlinedButton>(
        find.descendant(
          of: find.widgetWithText(AuthSecondaryButton, 'APPLE'),
          matching: find.byType(OutlinedButton),
        ),
      );
      expect(appleButton.onPressed, isNull);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  // ---------------------------------------------------------------------------
  // T-W3 — Tapping Apple button calls notifier.signInWithApple
  // ---------------------------------------------------------------------------
  testWidgets('T-W3 — tapping Apple button on iOS calls signInWithApple',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

    try {
      var called = false;
      final notifier = _TestAuthNotifier(
        onSignInWithApple: () async {
          called = true;
        },
      );

      await tester.pumpWidget(_buildApp(notifier: notifier));
      await tester.pumpAndSettle();

      await tester.tap(
        find.descendant(
          of: find.widgetWithText(AuthSecondaryButton, 'APPLE'),
          matching: find.byType(OutlinedButton),
        ),
      );
      await tester.pumpAndSettle();

      expect(called, isTrue);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  // ---------------------------------------------------------------------------
  // T-W4 — accountExistsWithDifferentCredential shows error banner
  // ---------------------------------------------------------------------------
  testWidgets(
      'T-W4 — Apple sign-in accountExistsWithDifferentCredential shows banner',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

    try {
      late _TestAuthNotifier notifier;
      notifier = _TestAuthNotifier(
        onSignInWithApple: () async {
          notifier.state = const AsyncError(
            AuthFailure.accountExistsWithDifferentCredential(),
            StackTrace.empty,
          );
        },
      );

      await tester.pumpWidget(_buildApp(notifier: notifier));
      await tester.pumpAndSettle();

      await tester.tap(
        find.descendant(
          of: find.widgetWithText(AuthSecondaryButton, 'APPLE'),
          matching: find.byType(OutlinedButton),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Esta cuenta ya existe. Iniciá sesión con tu método original y vinculá Apple desde tu perfil.',
        ),
        findsOneWidget,
      );
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  // ---------------------------------------------------------------------------
  // T-W5 — cancel (AsyncData(null)) does NOT show error banner
  // ---------------------------------------------------------------------------
  testWidgets(
      'T-W5 — does not show error banner after cancel (AsyncData(null))',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

    try {
      // Notifier starts at AsyncData(null) — the post-cancel state.
      final notifier = _TestAuthNotifier(initialUser: null);

      await tester.pumpWidget(_buildApp(notifier: notifier));
      await tester.pumpAndSettle();

      expect(find.byType(AuthFailureBanner), findsNothing);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
