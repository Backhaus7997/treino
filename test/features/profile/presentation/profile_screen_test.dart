import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/auth/application/auth_providers.dart';
import 'package:treino/features/feed/application/friendship_providers.dart';
import 'package:treino/features/profile/application/profile_stats_providers.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';
import 'package:treino/features/profile/domain/user_session_stats.dart';
import 'package:treino/features/profile/presentation/widgets/profile_avatar_card.dart';
import 'package:treino/features/profile/presentation/widgets/profile_cuenta_section.dart';
import 'package:treino/features/profile/presentation/widgets/profile_header.dart';
import 'package:treino/features/profile/profile_screen.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

UserProfile _profile() => UserProfile(
      uid: 'uid-test',
      email: 'test@test.com',
      displayName: 'Test User',
      role: UserRole.athlete,
      createdAt: DateTime(2025),
      updatedAt: DateTime(2025),
    );

Widget _buildProfileScreen() {
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
          GoRoute(
            path: 'settings',
            builder: (_, __) => const Scaffold(body: Text('SETTINGS')),
          ),
        ],
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      authStateChangesProvider.overrideWith((_) => Stream.value(null)),
      userProfileProvider.overrideWith((_) => Stream.value(_profile())),
      pendingRequestCountProvider('').overrideWith((_) => 0),
      pendingRequestsStreamProvider('').overrideWith((_) => Stream.value([])),
      userSessionStatsProvider.overrideWith(
        (_) async => const UserSessionStats(
            totalSessions: 0, totalVolumeKg: 0, streak: 0),
      ),
    ],
    child: MaterialApp.router(
      theme: AppTheme.dark(),
      routerConfig: router,
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests — SCENARIO-507 (composition), SCENARIO-509 (Cerrar sesión present)
// ---------------------------------------------------------------------------

void main() {
  group('ProfileScreen', () {
    // SCENARIO-507: ProfileScreen contains ProfileHeader, ProfileAvatarCard,
    // ProfileCuentaSection in body
    testWidgets(
        'SCENARIO-507: ProfileScreen body contains ProfileHeader, ProfileAvatarCard, ProfileCuentaSection',
        (tester) async {
      await tester.pumpWidget(_buildProfileScreen());
      await tester.pumpAndSettle();

      expect(find.byType(ProfileHeader), findsOneWidget);
      expect(find.byType(ProfileAvatarCard), findsOneWidget);
      expect(find.byType(ProfileCuentaSection), findsOneWidget);
    });

    // SCENARIO-509: "Cerrar sesión" TextButton is present in ProfileScreen body footer
    testWidgets(
        'SCENARIO-509: "Cerrar sesión" TextButton is present in body footer',
        (tester) async {
      await tester.pumpWidget(_buildProfileScreen());
      await tester.pumpAndSettle();

      expect(find.text('Cerrar sesión'), findsOneWidget);
    });
  });
}
