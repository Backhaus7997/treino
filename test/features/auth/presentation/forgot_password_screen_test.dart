import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/features/auth/application/auth_notifier.dart';
import 'package:treino/features/auth/application/auth_providers.dart';
import 'package:treino/features/auth/domain/auth_failure.dart';
import 'package:treino/features/auth/presentation/forgot_password_screen.dart';
import 'package:treino/features/auth/presentation/widgets/auth_primary_button.dart';

class MockUser extends Mock implements User {}

class _TestAuthNotifier extends AuthNotifier {
  _TestAuthNotifier({this.onReset});
  Future<void> Function(String email)? onReset;

  @override
  Future<User?> build() async => null;

  @override
  Future<void> sendPasswordResetEmail({required String email}) async {
    if (onReset != null) await onReset!(email);
  }
}

GoRouter _makeRouter(Widget home) => GoRouter(
      initialLocation: '/forgot-password',
      routes: [
        GoRoute(path: '/forgot-password', builder: (_, __) => home),
        GoRoute(
          path: '/login',
          builder: (_, __) => const Scaffold(body: Text('LOGIN')),
        ),
      ],
    );

Widget _buildApp({required _TestAuthNotifier notifier}) {
  const screen = ForgotPasswordScreen();
  final router = _makeRouter(screen);
  return ProviderScope(
    overrides: [authNotifierProvider.overrideWith(() => notifier)],
    child: MaterialApp.router(routerConfig: router),
  );
}

void main() {
  // ---------------------------------------------------------------------------
  // Scenario 10.1: happy path — success message shown, field non-editable
  // ---------------------------------------------------------------------------
  testWidgets('scenario 10.1 — success message visible after submit',
      (tester) async {
    final notifier = _TestAuthNotifier(onReset: (_) async {});

    await tester.pumpWidget(_buildApp(notifier: notifier));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byType(TextFormField),
      'user@example.com',
    );
    await tester.pump();

    await tester.tap(find.byType(AuthPrimaryButton));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Te enviamos un email a user@example.com'),
      findsOneWidget,
    );
  });

  testWidgets('scenario 10.1 — field is read-only after success',
      (tester) async {
    final notifier = _TestAuthNotifier(onReset: (_) async {});

    await tester.pumpWidget(_buildApp(notifier: notifier));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField), 'user@example.com');
    await tester.pump();
    await tester.tap(find.byType(AuthPrimaryButton));
    await tester.pumpAndSettle();

    // Field should be non-editable (enabled: false)
    final tf = tester.widget<TextFormField>(find.byType(TextFormField));
    expect(tf.enabled, isFalse);
  });

  // ---------------------------------------------------------------------------
  // Scenario 11.1: userNotFound MASKED as success (security requirement)
  // ---------------------------------------------------------------------------
  testWidgets(
      'scenario 11.1 — userNotFound shows SUCCESS copy, not error banner',
      (tester) async {
    final notifier = _TestAuthNotifier(
      onReset: (_) async {
        throw const AuthFailure.userNotFound();
      },
    );

    await tester.pumpWidget(_buildApp(notifier: notifier));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byType(TextFormField),
      'ghost@example.com',
    );
    await tester.pump();

    await tester.tap(find.byType(AuthPrimaryButton));
    await tester.pumpAndSettle();

    // Should show success message, NOT an error banner
    expect(
      find.textContaining('Te enviamos un email a ghost@example.com'),
      findsOneWidget,
    );
    expect(
      find.text('No encontramos una cuenta con ese email'),
      findsNothing,
    );
  });

  // ---------------------------------------------------------------------------
  // Network error → banner shown (NOT masked)
  // ---------------------------------------------------------------------------
  testWidgets('network error shows error banner', (tester) async {
    final notifier = _TestAuthNotifier(
      onReset: (_) async {
        throw const AuthFailure.networkError();
      },
    );

    await tester.pumpWidget(_buildApp(notifier: notifier));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField), 'user@example.com');
    await tester.pump();

    await tester.tap(find.byType(AuthPrimaryButton));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Sin conexión'),
      findsOneWidget,
    );
  });

  // ---------------------------------------------------------------------------
  // REQ-AUTH-026: spinner during loading (local _isLoading state)
  // ---------------------------------------------------------------------------
  testWidgets('spinner shown while submit is in progress', (tester) async {
    // Use a completer so sendPasswordResetEmail never resolves during the test.
    final completer = Completer<void>();
    late _TestAuthNotifier notifier;
    notifier = _TestAuthNotifier(onReset: (_) => completer.future);

    await tester.pumpWidget(_buildApp(notifier: notifier));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField), 'user@example.com');
    await tester.pump();

    // Tap submit and pump once — _submit sets _isLoading=true synchronously
    // before awaiting the completer, so the spinner is visible after one pump.
    await tester.tap(find.byType(AuthPrimaryButton));
    await tester.pump(); // allow setState(_isLoading=true) to render

    // The button should show the spinner (isLoading:true on AuthPrimaryButton)
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
