import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/router.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/auth/application/auth_providers.dart';
import 'package:treino/features/feed/application/friendship_providers.dart';
import 'package:treino/features/feed/presentation/friend_requests_inbox_screen.dart';
import 'package:treino/features/profile/application/profile_stats_providers.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';
import 'package:treino/features/profile/domain/user_session_stats.dart';
import 'package:treino/features/profile/presentation/profile_edit_personal_screen.dart';
import 'package:treino/features/profile/presentation/profile_gym_screen.dart';
import 'package:treino/features/profile/presentation/profile_routines_screen.dart';
import 'package:treino/features/profile/presentation/profile_settings_screen.dart';

// ---------------------------------------------------------------------------
// Shared test scaffolding
// ---------------------------------------------------------------------------

UserProfile _testProfile() => UserProfile(
      uid: 'uid-test',
      email: 'test@test.com',
      displayName: 'Test User',
      role: UserRole.athlete,
      createdAt: DateTime(2025),
      updatedAt: DateTime(2025),
    );

List<Override> _baseOverrides() => [
      authStateChangesProvider.overrideWith((_) => Stream.value(null)),
      userSessionStatsProvider.overrideWith(
        (_) async => const UserSessionStats(
            totalSessions: 0, totalVolumeKg: 0, streak: 0),
      ),
      pendingRequestCountProvider('').overrideWith((_) => 0),
      pendingRequestsStreamProvider('').overrideWith((_) => Stream.value([])),
      userProfileProvider
          .overrideWith((_) => Stream.value(_testProfile())),
    ];

// ---------------------------------------------------------------------------
// Tests: SCENARIO-468b — route registration in production router
// Tests: SCENARIO-507, SCENARIO-508 — new sub-routes + existing route intact
// ---------------------------------------------------------------------------

void main() {
  group('Router — /profile/friend-requests route (SCENARIO-468b)', () {
    testWidgets(
        'SCENARIO-468b: pushing /profile/friend-requests renders FriendRequestsInboxScreen',
        (tester) async {
      // Use a ProviderContainer so we can pass ref.read to buildRouter.
      final container = ProviderContainer(
        overrides: [
          authStateChangesProvider.overrideWith(
            (_) => Stream.value(null),
          ),
          userSessionStatsProvider.overrideWith(
            (_) async => const UserSessionStats(
                totalSessions: 0, totalVolumeKg: 0, streak: 0),
          ),
          pendingRequestCountProvider('').overrideWith((_) => 0),
          pendingRequestsStreamProvider('').overrideWith(
            (_) => Stream.value([]),
          ),
        ],
      );
      addTearDown(container.dispose);

      // Build the production router using the container's ref.read.
      final router = buildRouter(
        refreshListenable: ValueNotifier<int>(0),
        read: container.read,
      );

      // Navigate straight to /profile/friend-requests so we bypass
      // the authRedirect logic (which requires a full auth setup).
      router.go('/profile/friend-requests');

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            theme: AppTheme.dark(),
            routerConfig: router,
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.byType(FriendRequestsInboxScreen), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------------
  // SCENARIO-507: all 4 new sub-routes resolve without routing error
  // ---------------------------------------------------------------------------
  group('Router — new profile sub-routes (SCENARIO-507)', () {
    testWidgets(
        'SCENARIO-507a: /profile/edit-personal resolves to ProfileEditPersonalScreen',
        (tester) async {
      final container = ProviderContainer(overrides: _baseOverrides());
      addTearDown(container.dispose);
      final router = buildRouter(
        refreshListenable: ValueNotifier<int>(0),
        read: container.read,
      );
      router.go('/profile/edit-personal');
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            theme: AppTheme.dark(),
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ProfileEditPersonalScreen), findsOneWidget);
    });

    testWidgets(
        'SCENARIO-507b: /profile/gym resolves to ProfileGymScreen',
        (tester) async {
      final container = ProviderContainer(overrides: _baseOverrides());
      addTearDown(container.dispose);
      final router = buildRouter(
        refreshListenable: ValueNotifier<int>(0),
        read: container.read,
      );
      router.go('/profile/gym');
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            theme: AppTheme.dark(),
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ProfileGymScreen), findsOneWidget);
    });

    testWidgets(
        'SCENARIO-507c: /profile/routines resolves to ProfileRoutinesScreen',
        (tester) async {
      final container = ProviderContainer(overrides: _baseOverrides());
      addTearDown(container.dispose);
      final router = buildRouter(
        refreshListenable: ValueNotifier<int>(0),
        read: container.read,
      );
      router.go('/profile/routines');
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            theme: AppTheme.dark(),
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ProfileRoutinesScreen), findsOneWidget);
    });

    testWidgets(
        'SCENARIO-507d: /profile/settings resolves to ProfileSettingsScreen',
        (tester) async {
      final container = ProviderContainer(overrides: _baseOverrides());
      addTearDown(container.dispose);
      final router = buildRouter(
        refreshListenable: ValueNotifier<int>(0),
        read: container.read,
      );
      router.go('/profile/settings');
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            theme: AppTheme.dark(),
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ProfileSettingsScreen), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------------
  // SCENARIO-508: /profile/friend-requests still navigates to FriendRequestsInboxScreen
  // after PR#1 changes (regression guard)
  // ---------------------------------------------------------------------------
  group('Router — /profile/friend-requests not broken by PR#1 (SCENARIO-508)', () {
    testWidgets(
        'SCENARIO-508: /profile/friend-requests still renders FriendRequestsInboxScreen',
        (tester) async {
      final container = ProviderContainer(overrides: _baseOverrides());
      addTearDown(container.dispose);
      final router = buildRouter(
        refreshListenable: ValueNotifier<int>(0),
        read: container.read,
      );
      router.go('/profile/friend-requests');
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            theme: AppTheme.dark(),
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(FriendRequestsInboxScreen), findsOneWidget);
    });
  });
}
