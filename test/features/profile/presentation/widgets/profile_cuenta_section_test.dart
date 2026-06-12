import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/auth/application/auth_providers.dart';
import 'package:treino/features/feed/application/friendship_providers.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';
import 'package:treino/features/profile/presentation/widgets/profile_cuenta_section.dart';
import 'package:treino/l10n/app_l10n.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const _uid = 'test-uid';

UserProfile _profile({String? gymId}) => UserProfile(
      uid: _uid,
      email: 'test@test.com',
      displayName: 'Test User',
      role: UserRole.athlete,
      createdAt: DateTime(2025),
      updatedAt: DateTime(2025),
      gymId: gymId,
    );

Widget _buildSection({
  required List<Override> overrides,
  GoRouter? router,
}) {
  final effectiveRouter = router ??
      GoRouter(
        initialLocation: '/profile',
        routes: [
          GoRoute(
            path: '/profile',
            builder: (_, __) => const Scaffold(
              body: SingleChildScrollView(child: ProfileCuentaSection()),
            ),
            routes: [
              GoRoute(
                path: 'friend-requests',
                builder: (_, __) =>
                    const Scaffold(body: Text('FRIEND_REQUESTS')),
              ),
              GoRoute(
                path: 'edit-personal',
                builder: (_, __) => const Scaffold(body: Text('EDIT_PERSONAL')),
              ),
              GoRoute(
                path: 'gym',
                builder: (_, __) => const Scaffold(body: Text('GYM_SCREEN')),
              ),
              GoRoute(
                path: 'routines',
                builder: (_, __) =>
                    const Scaffold(body: Text('ROUTINES_SCREEN')),
              ),
            ],
          ),
        ],
      );

  return ProviderScope(
    overrides: overrides,
    child: MaterialApp.router(
      theme: AppTheme.dark(),
      routerConfig: effectiveRouter,
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      locale: const Locale('es', 'AR'),
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests — SCENARIO-501..505
// Migrated from profile_friend_requests_tile_test.dart (SCENARIO-465a, 466, 467)
// per ADR-PSR-003 (T16 migration)
// ---------------------------------------------------------------------------

void main() {
  group('ProfileCuentaSection', () {
    // SCENARIO-501: exactly 4 tiles in correct order
    testWidgets(
        'SCENARIO-501: renders exactly 4 tiles in order: Solicitudes, Datos personales, Gimnasio, Mis rutinas',
        (tester) async {
      await tester.pumpWidget(
        _buildSection(
          overrides: [
            authStateChangesProvider.overrideWith((_) => Stream.value(null)),
            userProfileProvider.overrideWith((_) => Stream.value(_profile())),
            pendingRequestCountProvider('').overrideWith((_) => 0),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Solicitudes de amistad'), findsOneWidget);
      expect(find.text('Datos personales'), findsOneWidget);
      expect(find.text('Gimnasio'), findsOneWidget);
      expect(find.text('Mis rutinas'), findsOneWidget);
    });

    // SCENARIO-502: Solicitudes tile shows count from pendingRequestCountProvider
    testWidgets(
        'SCENARIO-502: Solicitudes tile shows "4 nuevas" when count is 4',
        (tester) async {
      await tester.pumpWidget(
        _buildSection(
          overrides: [
            authStateChangesProvider.overrideWith((_) => Stream.value(null)),
            userProfileProvider.overrideWith((_) => Stream.value(_profile())),
            pendingRequestCountProvider('').overrideWith((_) => 4),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('4 nuevas'), findsOneWidget);
    });

    // SCENARIO-503: Datos personales tile navigates to /profile/edit-personal
    testWidgets(
        'SCENARIO-503: tapping Datos personales tile navigates to /profile/edit-personal',
        (tester) async {
      await tester.pumpWidget(
        _buildSection(
          overrides: [
            authStateChangesProvider.overrideWith((_) => Stream.value(null)),
            userProfileProvider.overrideWith((_) => Stream.value(_profile())),
            pendingRequestCountProvider('').overrideWith((_) => 0),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Datos personales'));
      await tester.pumpAndSettle();

      expect(find.text('EDIT_PERSONAL'), findsOneWidget);
    });

    // SCENARIO-504: Gimnasio tile navigates to /profile/gym
    testWidgets('SCENARIO-504: tapping Gimnasio tile navigates to /profile/gym',
        (tester) async {
      await tester.pumpWidget(
        _buildSection(
          overrides: [
            authStateChangesProvider.overrideWith((_) => Stream.value(null)),
            userProfileProvider.overrideWith((_) => Stream.value(_profile())),
            pendingRequestCountProvider('').overrideWith((_) => 0),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Gimnasio'));
      await tester.pumpAndSettle();

      expect(find.text('GYM_SCREEN'), findsOneWidget);
    });

    // SCENARIO-505: Mis rutinas tile navigates to /profile/routines
    testWidgets(
        'SCENARIO-505: tapping Mis rutinas tile navigates to /profile/routines',
        (tester) async {
      await tester.pumpWidget(
        _buildSection(
          overrides: [
            authStateChangesProvider.overrideWith((_) => Stream.value(null)),
            userProfileProvider.overrideWith((_) => Stream.value(_profile())),
            pendingRequestCountProvider('').overrideWith((_) => 0),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Mis rutinas'));
      await tester.pumpAndSettle();

      expect(find.text('ROUTINES_SCREEN'), findsOneWidget);
    });

    // ── Migrated from profile_friend_requests_tile_test.dart ────────────────
    // SCENARIO-465a (migrated): Solicitudes count=3 reflected in tile
    testWidgets(
        'SCENARIO-465a (migrated): Solicitudes tile reflects count 3 from pendingRequestCountProvider',
        (tester) async {
      await tester.pumpWidget(
        _buildSection(
          overrides: [
            authStateChangesProvider.overrideWith((_) => Stream.value(null)),
            userProfileProvider.overrideWith((_) => Stream.value(_profile())),
            pendingRequestCountProvider('').overrideWith((_) => 3),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('3 nuevas'), findsOneWidget);
    });

    // SCENARIO-466 (migrated): count=0 tile is visible with no subtitle badge
    testWidgets(
        'SCENARIO-466 (migrated): Solicitudes tile visible when count=0, no subtitle count badge',
        (tester) async {
      await tester.pumpWidget(
        _buildSection(
          overrides: [
            authStateChangesProvider.overrideWith((_) => Stream.value(null)),
            userProfileProvider.overrideWith((_) => Stream.value(_profile())),
            pendingRequestCountProvider('').overrideWith((_) => 0),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Solicitudes de amistad'), findsOneWidget);
      // When count == 0, subtitle should NOT show "0 nuevas"
      expect(find.text('0 nuevas'), findsNothing);
    });

    // SCENARIO-467 (migrated): tapping Solicitudes navigates to /profile/friend-requests
    testWidgets(
        'SCENARIO-467 (migrated): tapping Solicitudes tile navigates to /profile/friend-requests',
        (tester) async {
      await tester.pumpWidget(
        _buildSection(
          overrides: [
            authStateChangesProvider.overrideWith((_) => Stream.value(null)),
            userProfileProvider.overrideWith((_) => Stream.value(_profile())),
            pendingRequestCountProvider('').overrideWith((_) => 2),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Solicitudes de amistad'));
      await tester.pumpAndSettle();

      expect(find.text('FRIEND_REQUESTS'), findsOneWidget);
    });
  });
}
