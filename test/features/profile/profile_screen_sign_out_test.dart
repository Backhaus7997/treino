import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/features/auth/application/auth_notifier.dart';
import 'package:treino/features/auth/application/auth_providers.dart';
import 'package:treino/features/profile/profile_screen.dart';

class MockUser extends Mock implements User {}

class _TestAuthNotifier extends AuthNotifier {
  _TestAuthNotifier(this._user);
  final User _user;
  int signOutCallCount = 0;

  @override
  Future<User?> build() async => _user;

  @override
  Future<void> signOut() async {
    signOutCallCount++;
  }
}

void main() {
  testWidgets('scenario 12.3 — tap Cerrar sesión calls signOut exactly once',
      (tester) async {
    final user = MockUser();
    when(() => user.emailVerified).thenReturn(true);

    final notifier = _TestAuthNotifier(user);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [authNotifierProvider.overrideWith(() => notifier)],
        child: const MaterialApp(home: Scaffold(body: ProfileScreen())),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cerrar sesión'));
    await tester.pumpAndSettle();

    expect(notifier.signOutCallCount, 1);
  });
}
