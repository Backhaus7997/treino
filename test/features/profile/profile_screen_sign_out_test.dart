import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/auth/application/auth_notifier.dart';
import 'package:treino/features/auth/application/auth_providers.dart';
import 'package:treino/features/feed/application/friendship_providers.dart';
import 'package:treino/features/profile/application/profile_stats_providers.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';
import 'package:treino/features/profile/domain/user_session_stats.dart';
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

UserProfile _testProfile() => UserProfile(
      uid: 'uid-test',
      email: 'test@test.com',
      displayName: 'Test User',
      role: UserRole.athlete,
      createdAt: DateTime(2025),
      updatedAt: DateTime(2025),
    );

void main() {
  testWidgets('scenario 12.3 — tap Cerrar sesión calls signOut exactly once',
      (tester) async {
    final user = MockUser();
    when(() => user.emailVerified).thenReturn(true);

    final notifier = _TestAuthNotifier(user);

    // ProfileScreen now uses context.push (via ProfileHeader / ProfileCuentaSection)
    // so it requires a GoRouter context.
    final router = GoRouter(
      initialLocation: '/profile',
      routes: [
        GoRoute(
          path: '/profile',
          builder: (_, __) => const Scaffold(body: ProfileScreen()),
          routes: [
            GoRoute(
              path: 'friend-requests',
              builder: (_, __) => const Scaffold(body: Text('FRIEND_REQUESTS')),
            ),
            GoRoute(
              path: 'edit-personal',
              builder: (_, __) => const Scaffold(body: Text('EDIT_PERSONAL')),
            ),
            GoRoute(
              path: 'gym',
              builder: (_, __) => const Scaffold(body: Text('GYM')),
            ),
            GoRoute(
              path: 'routines',
              builder: (_, __) => const Scaffold(body: Text('ROUTINES')),
            ),
            // settings route REMOVED 2026-05-28 — PR#4 pivot
          ],
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authNotifierProvider.overrideWith(() => notifier),
          authStateChangesProvider.overrideWith((_) => Stream.value(null)),
          userProfileProvider.overrideWith((_) => Stream.value(_testProfile())),
          pendingRequestCountProvider('').overrideWith((_) => 0),
          pendingRequestsStreamProvider('').overrideWith(
            (_) => Stream.value([]),
          ),
          userSessionStatsProvider.overrideWith(
            (_) async => const UserSessionStats(
                totalSessions: 0, totalVolumeKg: 0, streak: 0),
          ),
        ],
        child: MaterialApp.router(
          theme: AppTheme.dark(),
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Scroll to ensure the footer button is visible in the viewport.
    await tester.scrollUntilVisible(find.text('Cerrar sesión'), 50);
    await tester.tap(find.text('Cerrar sesión'));
    await tester.pumpAndSettle();

    expect(notifier.signOutCallCount, 1);
  });
}
