import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/auth/application/auth_providers.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';
import 'package:treino/features/profile/presentation/widgets/profile_avatar_card.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

UserProfile _profile({
  String displayName = 'Maria Gomez',
  String? gymId,
  String? avatarUrl,
}) =>
    UserProfile(
      uid: 'uid-test',
      email: 'test@test.com',
      displayName: displayName,
      role: UserRole.athlete,
      createdAt: DateTime(2025),
      updatedAt: DateTime(2025),
      gymId: gymId,
      avatarUrl: avatarUrl,
    );

Widget _buildCard({
  required UserProfile profile,
  GoRouter? router,
}) {
  final effectiveRouter = router ??
      GoRouter(
        initialLocation: '/profile',
        routes: [
          GoRoute(
            path: '/profile',
            builder: (_, __) => const Scaffold(
              body: ProfileAvatarCard(),
            ),
          ),
        ],
      );

  return ProviderScope(
    overrides: [
      authStateChangesProvider.overrideWith((_) => Stream.value(null)),
      userProfileProvider.overrideWith((_) => Stream.value(profile)),
    ],
    child: MaterialApp.router(
      theme: AppTheme.dark(),
      routerConfig: effectiveRouter,
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests — SCENARIO-496..500
// ---------------------------------------------------------------------------

void main() {
  group('ProfileAvatarCard', () {
    // SCENARIO-496: renders avatar, displayName, and derived @handle
    testWidgets(
        'SCENARIO-496: renders displayName and derived @handle for "Maria Gomez"',
        (tester) async {
      await tester.pumpWidget(_buildCard(profile: _profile()));
      await tester.pumpAndSettle();

      // Display name is uppercased on render (mockup parity 2026-06-01 polish).
      // The @handle derivation still operates on the raw displayName, so the
      // handle stays lowercase.
      expect(find.text('MARIA GOMEZ'), findsOneWidget);
      expect(find.text('@maria.gomez'), findsOneWidget);
    });

    // SCENARIO-497: @handle derivation preserves accented chars and lowercase
    testWidgets('SCENARIO-497: @handle for "Ana Núñez" becomes "@ana.núñez"',
        (tester) async {
      await tester.pumpWidget(
        _buildCard(profile: _profile(displayName: 'Ana Núñez')),
      );
      await tester.pumpAndSettle();

      // Display name uppercased; handle derivation preserves accents.
      expect(find.text('ANA NÚÑEZ'), findsOneWidget);
      expect(find.text('@ana.núñez'), findsOneWidget);
    });

    // SCENARIO-498: gym chip visible when gymId non-null
    testWidgets('SCENARIO-498: gym chip visible when gymId is non-null',
        (tester) async {
      await tester.pumpWidget(
        _buildCard(profile: _profile(gymId: 'smart-fit-palermo')),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('profile_avatar_gym_chip')), findsOneWidget);
    });

    // SCENARIO-499: gym chip absent when gymId null
    testWidgets('SCENARIO-499: gym chip absent when gymId is null',
        (tester) async {
      await tester.pumpWidget(_buildCard(profile: _profile()));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('profile_avatar_gym_chip')), findsNothing);
    });

    // SCENARIO-500: REMOVED 2026-05-27 — pencil dropped from ProfileAvatarCard
    // (single edit entry point via "Datos personales" tile of CUENTA).
    // Guard test: card is read-only, pencil key MUST NOT exist.
    testWidgets(
        'SCENARIO-500 (guard): no pencil key — card is read-only after 2026-05-27',
        (tester) async {
      await tester.pumpWidget(_buildCard(profile: _profile()));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('profile_avatar_pencil')), findsNothing);
    });
  });
}
