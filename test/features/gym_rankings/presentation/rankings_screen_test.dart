// Phase 4 RED — SCENARIO-RANK-7
//
// RankingsScreen renders the 3 leaderboard dimensions (Rachas / Volumen /
// Lifts, lifts sub-split squat/bench/deadlift) for the current athlete's
// gym, using the ranking query providers (Phase 4.1/4.2). Uses
// AppPalette.of(context) (no hex) and TreinoIcon.X (no PhosphorIcons)
// per project standards.
//
// Spec `gym-rankings`:
//   - Streak/Volume/Main-Lift Leaderboards render per dimension.
//   - Gym Scoping and No-Gym Exclusion: athlete with no gym sees a
//     "no gym" state instead of a query.
//   - Empty States: gym with zero opted-in athletes → empty state per
//     dimension, not an error.

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/auth/application/auth_providers.dart';
import 'package:treino/features/gym_rankings/application/ranking_providers.dart';
import 'package:treino/features/gym_rankings/presentation/rankings_screen.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_public_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';
import 'package:treino/l10n/app_l10n.dart';

class MockUser extends Mock implements User {
  @override
  String get uid => 'test-uid';
}

const _uid = 'test-uid';
const _gymId = 'gym-a';

UserProfile _profile({String? gymId}) => UserProfile(
      uid: _uid,
      email: 'test@treino.app',
      displayName: 'Test',
      role: UserRole.athlete,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
      gymId: gymId,
    );

UserPublicProfile _rankedProfile({
  required String uid,
  required String displayName,
  int? racha,
  num? lifetimeVolumeKg,
  num? bestSquatKg,
  num? bestBenchKg,
  num? bestDeadliftKg,
}) =>
    UserPublicProfile(
      uid: uid,
      displayName: displayName,
      gymId: _gymId,
      rankingOptIn: true,
      racha: racha,
      lifetimeVolumeKg: lifetimeVolumeKg ?? 0,
      bestSquatKg: bestSquatKg,
      bestBenchKg: bestBenchKg,
      bestDeadliftKg: bestDeadliftKg,
    );

Widget _buildScreen({required List<Override> overrides}) {
  final router = GoRouter(
    initialLocation: '/profile/rankings',
    routes: [
      GoRoute(
        path: '/profile/rankings',
        builder: (_, __) => const Scaffold(body: RankingsScreen()),
      ),
    ],
  );
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp.router(
      theme: AppTheme.dark(),
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      locale: const Locale('es', 'AR'),
      routerConfig: router,
    ),
  );
}

void main() {
  group('RankingsScreen', () {
    final mockUser = MockUser();

    List<Override> baseOverrides({
      String? gymId = _gymId,
      List<UserPublicProfile> streak = const [],
      List<UserPublicProfile> volume = const [],
      List<UserPublicProfile> squat = const [],
      List<UserPublicProfile> bench = const [],
      List<UserPublicProfile> deadlift = const [],
    }) =>
        [
          authStateChangesProvider.overrideWith((_) => Stream.value(mockUser)),
          userProfileProvider.overrideWith(
            (_) => Stream.value(_profile(gymId: gymId)),
          ),
          streakLeaderboardProvider(gymId ?? '')
              .overrideWith((_) async => streak),
          volumeLeaderboardProvider(gymId ?? '')
              .overrideWith((_) async => volume),
          squatLeaderboardProvider(gymId ?? '')
              .overrideWith((_) async => squat),
          benchLeaderboardProvider(gymId ?? '')
              .overrideWith((_) async => bench),
          deadliftLeaderboardProvider(gymId ?? '')
              .overrideWith((_) async => deadlift),
        ];

    testWidgets('renders the 3 dimension section headers', (tester) async {
      await tester.pumpWidget(_buildScreen(overrides: baseOverrides()));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('rankings_section_streak')), findsOneWidget);
      expect(find.byKey(const Key('rankings_section_volume')), findsOneWidget);
      expect(find.byKey(const Key('rankings_section_lifts')), findsOneWidget);
    });

    testWidgets('lifts section renders squat/bench/deadlift sub-split tabs',
        (tester) async {
      await tester.pumpWidget(_buildScreen(overrides: baseOverrides()));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('rankings_lift_tab_squat')), findsOneWidget);
      expect(find.byKey(const Key('rankings_lift_tab_bench')), findsOneWidget);
      expect(
          find.byKey(const Key('rankings_lift_tab_deadlift')), findsOneWidget);
    });

    testWidgets('streak leaderboard renders athletes ordered by racha',
        (tester) async {
      await tester.pumpWidget(_buildScreen(
        overrides: baseOverrides(
          streak: [
            _rankedProfile(uid: 'u2', displayName: 'Lu', racha: 12),
            _rankedProfile(uid: 'u3', displayName: 'Coti', racha: 8),
          ],
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Lu'), findsOneWidget);
      expect(find.text('Coti'), findsOneWidget);
      expect(find.text('12'), findsOneWidget);
      expect(find.text('8'), findsOneWidget);
    });

    testWidgets('current user is highlighted when present in a leaderboard',
        (tester) async {
      await tester.pumpWidget(_buildScreen(
        overrides: baseOverrides(
          streak: [
            _rankedProfile(uid: 'u2', displayName: 'Lu', racha: 12),
            _rankedProfile(uid: _uid, displayName: 'Yo', racha: 8),
          ],
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('rankings_row_$_uid')), findsWidgets);
    });

    testWidgets('empty state renders when the gym has zero opted-in athletes',
        (tester) async {
      await tester.pumpWidget(_buildScreen(overrides: baseOverrides()));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('rankings_empty_streak')), findsOneWidget);
    });

    testWidgets(
        'no-gym state renders instead of leaderboards when the athlete has '
        'no gym', (tester) async {
      await tester.pumpWidget(_buildScreen(
          overrides: baseOverrides(
        gymId: null,
      )));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('rankings_no_gym_state')), findsOneWidget);
      expect(find.byKey(const Key('rankings_section_streak')), findsNothing);
    });

    testWidgets('loading state renders while the athlete profile resolves',
        (tester) async {
      await tester.pumpWidget(_buildScreen(overrides: [
        authStateChangesProvider.overrideWith((_) => Stream.value(mockUser)),
        userProfileProvider.overrideWith(
          (_) => const Stream<UserProfile?>.empty(),
        ),
      ]));
      // Pump once (not settle) — the profile stream never emits so the
      // screen must be showing a loading state, not an empty crash.
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsWidgets);
    });
  });
}
