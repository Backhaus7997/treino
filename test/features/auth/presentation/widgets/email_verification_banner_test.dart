import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/features/auth/application/auth_notifier.dart';
import 'package:treino/features/auth/application/auth_providers.dart';
import 'package:treino/features/auth/presentation/widgets/email_verification_banner.dart';

class MockUser extends Mock implements User {}

class _TestAuthNotifier extends AuthNotifier {
  _TestAuthNotifier(this._user);
  final User? _user;
  bool sendVerificationCalled = false;

  @override
  Future<User?> build() async => _user;

  @override
  Future<void> sendEmailVerification() async {
    sendVerificationCalled = true;
  }
}

Widget _buildApp({required _TestAuthNotifier notifier}) {
  return ProviderScope(
    overrides: [authNotifierProvider.overrideWith(() => notifier)],
    child: const MaterialApp(
      home: Scaffold(body: EmailVerificationBanner()),
    ),
  );
}

void main() {
  // ---------------------------------------------------------------------------
  // Scenario 13.1 — visible when emailVerified == false
  // ---------------------------------------------------------------------------
  testWidgets('scenario 13.1 — banner visible when emailVerified is false',
      (tester) async {
    final user = MockUser();
    when(() => user.emailVerified).thenReturn(false);

    await tester.pumpWidget(_buildApp(notifier: _TestAuthNotifier(user)));
    await tester.pumpAndSettle();

    expect(find.byType(EmailVerificationBanner), findsOneWidget);
    // Banner content should include the title
    expect(find.textContaining('Verificá tu email'), findsOneWidget);
  });

  // ---------------------------------------------------------------------------
  // Scenario 13.2 — hidden when emailVerified == true
  // ---------------------------------------------------------------------------
  testWidgets('scenario 13.2 — banner hidden when emailVerified is true',
      (tester) async {
    final user = MockUser();
    when(() => user.emailVerified).thenReturn(true);

    await tester.pumpWidget(_buildApp(notifier: _TestAuthNotifier(user)));
    await tester.pumpAndSettle();

    // Banner should render nothing (SizedBox.shrink or empty)
    expect(find.textContaining('Verificá tu email'), findsNothing);
  });

  // ---------------------------------------------------------------------------
  // Scenario 13.3 — dismiss removes from tree in same session
  // ---------------------------------------------------------------------------
  testWidgets('scenario 13.3 — dismiss hides banner for the session',
      (tester) async {
    final user = MockUser();
    when(() => user.emailVerified).thenReturn(false);

    await tester.pumpWidget(_buildApp(notifier: _TestAuthNotifier(user)));
    await tester.pumpAndSettle();

    expect(find.textContaining('Verificá tu email'), findsOneWidget);

    // Tap dismiss button
    await tester.tap(find.text('Ahora no'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Verificá tu email'), findsNothing);
  });

  // ---------------------------------------------------------------------------
  // Scenario 14.2 — Reenviar calls sendEmailVerification exactly once
  // ---------------------------------------------------------------------------
  testWidgets('scenario 14.2 — Reenviar calls sendEmailVerification once',
      (tester) async {
    final user = MockUser();
    when(() => user.emailVerified).thenReturn(false);

    final notifier = _TestAuthNotifier(user);
    await tester.pumpWidget(_buildApp(notifier: notifier));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Reenviar'));
    await tester.pumpAndSettle();

    expect(notifier.sendVerificationCalled, isTrue);
  });
}
