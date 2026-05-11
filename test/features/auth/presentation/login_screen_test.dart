import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/features/auth/application/auth_notifier.dart';
import 'package:treino/features/auth/application/auth_providers.dart';
import 'package:treino/features/auth/domain/auth_failure.dart';
import 'package:treino/features/auth/presentation/login_screen.dart';
import 'package:treino/features/auth/presentation/widgets/auth_failure_banner.dart';
import 'package:treino/features/auth/presentation/widgets/auth_pill_button.dart';
import 'package:treino/features/auth/presentation/widgets/auth_secondary_button.dart';

class MockUser extends Mock implements User {}

// Notifier stub that immediately resolves to a fixed state and exposes
// controllable signIn/signInWithApple behaviour via callbacks.
class _TestAuthNotifier extends AuthNotifier {
  _TestAuthNotifier({
    this.onSignIn,
    this.onSignInWithApple,
    User? initialUser,
  }) : _initialUser = initialUser;

  final User? _initialUser;
  Future<void> Function(String email, String password)? onSignIn;
  Future<void> Function()? onSignInWithApple;

  @override
  Future<User?> build() async => _initialUser;

  @override
  Future<void> signIn({required String email, required String password}) async {
    if (onSignIn != null) {
      await onSignIn!(email, password);
    }
  }

  @override
  Future<void> signInWithApple() async {
    if (onSignInWithApple != null) {
      await onSignInWithApple!();
    }
  }
}

// GoRouter for tests — pushes to /home on navigation.
GoRouter _makeRouter(Widget home) => GoRouter(
      initialLocation: '/login',
      routes: [
        GoRoute(
          path: '/login',
          builder: (_, __) => home,
        ),
        GoRoute(
          path: '/home',
          builder: (_, __) => const Scaffold(body: Text('HOME')),
        ),
        GoRoute(
          path: '/register',
          builder: (_, __) => const Scaffold(body: Text('REGISTER')),
        ),
        GoRoute(
          path: '/forgot-password',
          builder: (_, __) => const Scaffold(body: Text('FORGOT')),
        ),
      ],
    );

Widget _buildApp({
  required _TestAuthNotifier notifier,
}) {
  const screen = LoginScreen();
  final router = _makeRouter(screen);
  return ProviderScope(
    overrides: [
      authNotifierProvider.overrideWith(() => notifier),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

void main() {
  late MockUser mockUser;

  setUp(() {
    mockUser = MockUser();
    when(() => mockUser.emailVerified).thenReturn(true);
  });

  // ---------------------------------------------------------------------------
  // REQ-AUTH-006: submit disabled when fields are empty
  // ---------------------------------------------------------------------------
  testWidgets('submit button disabled with empty fields', (tester) async {
    await tester.pumpWidget(_buildApp(notifier: _TestAuthNotifier()));
    await tester.pumpAndSettle();

    // Button should be disabled (onPressed is null)
    final btn = tester.widget<ElevatedButton>(
      find.descendant(
        of: find.byType(AuthPillButton),
        matching: find.byType(ElevatedButton),
      ),
    );
    expect(btn.onPressed, isNull);
  });

  // ---------------------------------------------------------------------------
  // Scenario 6.1: happy path → spinner → /home
  // ---------------------------------------------------------------------------
  testWidgets('scenario 6.1 — happy path submit navigates to /home',
      (tester) async {
    final notifier = _TestAuthNotifier(
      onSignIn: (email, password) async {
        // Simulate state transition to AsyncData(user)
        // The notifier's state will be set by the action
      },
    );

    // Override signIn to simulate success
    notifier.onSignIn = (email, password) async {
      notifier.state = AsyncData(mockUser);
    };

    await tester.pumpWidget(_buildApp(notifier: notifier));
    await tester.pumpAndSettle();

    // Fill in fields
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'test@example.com');
    await tester.enterText(fields.at(1), 'Pass1234');
    await tester.pump();

    // Tap submit
    await tester.tap(find.byType(AuthPillButton));
    await tester.pumpAndSettle();

    // Should have navigated to /home
    expect(find.text('HOME'), findsOneWidget);
  });

  // ---------------------------------------------------------------------------
  // Scenario 7.1: wrong password → banner with error copy
  // ---------------------------------------------------------------------------
  testWidgets('scenario 7.1 — wrong password banner shows error copy',
      (tester) async {
    final notifier = _TestAuthNotifier();
    notifier.onSignIn = (email, password) async {
      notifier.state =
          const AsyncError(AuthFailure.wrongPassword(), StackTrace.empty);
    };

    await tester.pumpWidget(_buildApp(notifier: notifier));
    await tester.pumpAndSettle();

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'test@example.com');
    await tester.enterText(fields.at(1), 'wrong');
    await tester.pump();

    await tester.tap(find.byType(AuthPillButton));
    await tester.pumpAndSettle();

    expect(find.text('La contraseña es incorrecta'), findsOneWidget);
  });

  // ---------------------------------------------------------------------------
  // Scenario 8.1: user not found → banner with error copy
  // ---------------------------------------------------------------------------
  testWidgets('scenario 8.1 — user not found banner shows error copy',
      (tester) async {
    final notifier = _TestAuthNotifier();
    notifier.onSignIn = (email, password) async {
      notifier.state =
          const AsyncError(AuthFailure.userNotFound(), StackTrace.empty);
    };

    await tester.pumpWidget(_buildApp(notifier: notifier));
    await tester.pumpAndSettle();

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'nouser@example.com');
    await tester.enterText(fields.at(1), 'Pass1234');
    await tester.pump();

    await tester.tap(find.byType(AuthPillButton));
    await tester.pumpAndSettle();

    expect(
        find.text('No encontramos una cuenta con ese email'), findsOneWidget);
  });

  // ---------------------------------------------------------------------------
  // REQ-AUTH-026: spinner during AsyncLoading
  // ---------------------------------------------------------------------------
  testWidgets('spinner shown during AsyncLoading', (tester) async {
    final notifier = _TestAuthNotifier();
    notifier.onSignIn = (email, password) async {
      // Set loading state and don't resolve
      notifier.state = const AsyncLoading();
    };

    await tester.pumpWidget(_buildApp(notifier: notifier));
    await tester.pumpAndSettle();

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'test@example.com');
    await tester.enterText(fields.at(1), 'Pass1234');
    await tester.pump();

    await tester.tap(find.byType(AuthPillButton));
    await tester.pump(); // Don't settle — keep in loading state

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  // ---------------------------------------------------------------------------
  // Links to /register and /forgot-password
  // ---------------------------------------------------------------------------
  testWidgets('link to /register navigates to register screen', (tester) async {
    await tester.pumpWidget(_buildApp(notifier: _TestAuthNotifier()));
    await tester.pumpAndSettle();

    // Scroll down to reveal the "Registrate" link (it may be below the fold).
    await tester.ensureVisible(find.text('Registrate'));
    await tester.tap(find.text('Registrate'));
    await tester.pumpAndSettle();

    expect(find.text('REGISTER'), findsOneWidget);
  });

  testWidgets('link to /forgot-password navigates to forgot screen',
      (tester) async {
    await tester.pumpWidget(_buildApp(notifier: _TestAuthNotifier()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Olvidé la contraseña'));
    await tester.pumpAndSettle();

    expect(find.text('FORGOT'), findsOneWidget);
  });

  // ---------------------------------------------------------------------------
  // T-6.1 — Apple button enabled on iOS
  // ---------------------------------------------------------------------------
  testWidgets('T-6.1 — Apple button has non-null onPressed on iOS',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

    try {
      await tester.pumpWidget(_buildApp(notifier: _TestAuthNotifier()));
      await tester.pumpAndSettle();

      // Find the Apple AuthSecondaryButton by label
      final appleButton = tester.widget<OutlinedButton>(
        find.descendant(
          of: find.widgetWithText(AuthSecondaryButton, 'APPLE'),
          matching: find.byType(OutlinedButton),
        ),
      );
      expect(appleButton.onPressed, isNotNull);

      // No 'Próximamente' tooltip on the Apple button
      // (When enabled, the Tooltip wrapper is not added)
      final tooltipsOnApple = tester
          .widgetList<Tooltip>(
            find.ancestor(
              of: find.widgetWithText(AuthSecondaryButton, 'APPLE'),
              matching: find.byType(Tooltip),
            ),
          )
          .where((t) => t.message == 'Próximamente')
          .toList();
      expect(tooltipsOnApple, isEmpty);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  // ---------------------------------------------------------------------------
  // T-6.2 — Apple button disabled (onPressed null) on Android
  // ---------------------------------------------------------------------------
  testWidgets('T-6.2 — Apple button has null onPressed on Android',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;

    try {
      await tester.pumpWidget(_buildApp(notifier: _TestAuthNotifier()));
      await tester.pumpAndSettle();

      final appleButton = tester.widget<OutlinedButton>(
        find.descendant(
          of: find.widgetWithText(AuthSecondaryButton, 'APPLE'),
          matching: find.byType(OutlinedButton),
        ),
      );
      expect(appleButton.onPressed, isNull);

      // 'Próximamente' tooltip must be visible on Android (AuthSecondaryButton adds it when disabled)
      final tooltips = tester.widgetList<Tooltip>(find.byType(Tooltip));
      final hasProximo = tooltips.any((t) => t.message == 'Próximamente');
      expect(hasProximo, isTrue);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  // ---------------------------------------------------------------------------
  // T-6.3 — Tapping Apple button calls notifier.signInWithApple
  // ---------------------------------------------------------------------------
  testWidgets('T-6.3 — tapping Apple button on iOS calls signInWithApple',
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
  // T-6.4 — accountExistsWithDifferentCredential shows error banner
  // ---------------------------------------------------------------------------
  testWidgets(
      'T-6.4 — Apple sign-in accountExistsWithDifferentCredential shows banner',
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
  // W-1 — REQ-CANCEL-003: no error banner shown after cancel (AsyncData(null))
  // ---------------------------------------------------------------------------
  testWidgets('does not show error banner after cancel (AsyncData(null))',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

    try {
      // Notifier that emits AsyncData(null) — the post-cancel state.
      // onSignInWithApple is not set so signInWithApple() is a no-op and
      // state stays at the initial AsyncData(null) from build().
      final notifier = _TestAuthNotifier(initialUser: null);

      await tester.pumpWidget(_buildApp(notifier: notifier));
      await tester.pumpAndSettle();

      // No banner should appear — state is AsyncData(null), not AsyncError.
      expect(find.byType(AuthFailureBanner), findsNothing);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
