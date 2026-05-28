import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:treino/features/auth/application/auth_notifier.dart';
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

// Stub AuthNotifier that tracks signOut calls.
class _TrackingAuthNotifier extends AuthNotifier {
  bool signOutCalled = false;

  @override
  Future<User?> build() async => null;

  @override
  Future<void> signOut() async {
    signOutCalled = true;
  }
}

// Shared notifier instance — reset per test if needed.
_TrackingAuthNotifier _notifier = _TrackingAuthNotifier();

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
        ],
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      authStateChangesProvider.overrideWith((_) => Stream.value(null)),
      authNotifierProvider.overrideWith(() => _notifier),
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
// Tests
// ---------------------------------------------------------------------------

void main() {
  setUp(() {
    // Fresh notifier per test to reset call tracking.
    _notifier = _TrackingAuthNotifier();
  });

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

    // SCENARIO-509: REMOVED — superseded by SCENARIO-529.
    // The legacy "Cerrar sesión" TextButton is replaced by a ProfileSectionTile
    // in PR#4 v2. SCENARIO-529 covers the new tile's presence.
    // testWidgets('SCENARIO-509: ...', ...)  ← REMOVED 2026-05-28

    // SCENARIO-529: ProfileScreen body renders "Cerrar sesión" + "Eliminar
    // cuenta" tiles below ProfileCuentaSection; legacy TextButton is absent.
    testWidgets(
        'SCENARIO-529: body renders "Cerrar sesión" + "Eliminar cuenta" tiles; legacy TextButton absent',
        (tester) async {
      await tester.pumpWidget(_buildProfileScreen());
      await tester.pumpAndSettle();

      // Both tiles must be present.
      expect(
          find.text('Cerrar sesión'), findsOneWidget); // i18n: Fase 6 Etapa 3
      expect(
          find.text('Eliminar cuenta'), findsOneWidget); // i18n: Fase 6 Etapa 3

      // Legacy TextButton must be gone — it was rendered as a TextButton widget.
      // Now "Cerrar sesión" is a ProfileSectionTile, not a TextButton.
      expect(
        find.ancestor(
          of: find.text('Cerrar sesión'),
          matching: find.byType(TextButton),
        ),
        findsNothing,
      );
    });

    // SCENARIO-530: Tapping "Cerrar sesión" tile calls signOut.
    testWidgets('SCENARIO-530: tapping "Cerrar sesión" tile calls signOut',
        (tester) async {
      await tester.pumpWidget(_buildProfileScreen());
      await tester.pumpAndSettle();

      // Tiles are below the fold — scroll to them first.
      await tester.scrollUntilVisible(
          find.text('Cerrar sesión'), 50); // i18n: Fase 6 Etapa 3
      await tester.tap(find.text('Cerrar sesión')); // i18n: Fase 6 Etapa 3
      await tester.pumpAndSettle();

      expect(_notifier.signOutCalled, isTrue);
    });

    // SCENARIO-531: Tapping "Eliminar cuenta" opens the stub sheet.
    testWidgets(
        'SCENARIO-531: tapping "Eliminar cuenta" opens stub sheet with expected copy',
        (tester) async {
      await tester.pumpWidget(_buildProfileScreen());
      await tester.pumpAndSettle();

      // Tiles are below the fold — scroll to them first.
      await tester.scrollUntilVisible(
          find.text('Eliminar cuenta'), 50); // i18n: Fase 6 Etapa 3
      await tester.tap(find.text('Eliminar cuenta')); // i18n: Fase 6 Etapa 3
      await tester.pumpAndSettle();

      // Sheet title text and CANCELAR button must appear.
      expect(find.text('CANCELAR'), findsOneWidget); // i18n: Fase 6 Etapa 3
      // The sheet must NOT have a destructive confirm button.
      expect(find.text('ELIMINAR'), findsNothing);
    });

    // SCENARIO-532: CANCELAR in the stub sheet closes it without action.
    testWidgets('SCENARIO-532: CANCELAR closes the stub sheet without action',
        (tester) async {
      await tester.pumpWidget(_buildProfileScreen());
      await tester.pumpAndSettle();

      // Tiles are below the fold — scroll to them first.
      await tester.scrollUntilVisible(
          find.text('Eliminar cuenta'), 50); // i18n: Fase 6 Etapa 3

      // Open sheet.
      await tester.tap(find.text('Eliminar cuenta')); // i18n: Fase 6 Etapa 3
      await tester.pumpAndSettle();

      expect(find.text('CANCELAR'), findsOneWidget); // i18n: Fase 6 Etapa 3

      // Tap CANCELAR — sheet should close.
      await tester.tap(find.text('CANCELAR')); // i18n: Fase 6 Etapa 3
      await tester.pumpAndSettle();

      expect(find.text('CANCELAR'), findsNothing);
      // No deletion was triggered (signOut not called either).
      expect(_notifier.signOutCalled, isFalse);
    });
  });
}
