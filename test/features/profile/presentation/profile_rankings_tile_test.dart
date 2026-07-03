// rankings-v2 Phase 3 RED (task 3.1) — remove the rankings entry point from
// ProfileScreen.
//
// Spec `gym-rankings` — ProfileScreen no longer exposes a rankings entry
// point: rankings moved to the athlete Entrenar tab (design
// `sdd/rankings-v2/design` AD-1/AD-3). ProfileScreen's ENTRENAMIENTO section
// MUST NOT render a rankings tile/toggle/link — the old `_RankingsTile`
// (which pushed `/profile/rankings` and carried the opt-in Switch) is
// removed.
//
// This file previously asserted the tile's PRESENCE (Phase 4 v1 —
// SCENARIO-RANK-8); Phase 3 of rankings-v2 flips those assertions to assert
// ABSENCE, per the REMOVED requirement `gym-rankings — Rankings Reachable
// via Profile Tile and /profile/rankings`.

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
import 'package:treino/features/profile/application/ranking_optin_controller_provider.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/application/user_public_profile_providers.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_public_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';
import 'package:treino/features/profile/domain/user_session_stats.dart';
import 'package:treino/features/profile/profile_screen.dart';
import 'package:treino/l10n/app_l10n.dart';

class MockUser extends Mock implements User {
  @override
  String get uid => 'uid-test';
}

class _StubAuthNotifier extends AuthNotifier {
  _StubAuthNotifier({User? user}) : _user = user;
  final User? _user;

  @override
  Future<User?> build() async => _user;

  @override
  Future<void> signOut() async {}
}

class _FakeRankingOptInController extends RankingOptInControllerBase {
  final List<String> enabledCalls = [];
  final List<String> disabledCalls = [];
  final List<String> syncCalls = [];

  @override
  Future<void> enableRankingOptIn(String uid) async {
    enabledCalls.add(uid);
  }

  @override
  Future<void> disableRankingOptIn(String uid) async {
    disabledCalls.add(uid);
  }

  @override
  Future<void> syncGymIfDesynced(String uid) async {
    syncCalls.add(uid);
  }
}

const _uid = 'uid-test';

UserProfile _testProfile() => UserProfile(
      uid: _uid,
      email: 'test@test.com',
      displayName: 'Test User',
      role: UserRole.athlete,
      createdAt: DateTime(2025),
      updatedAt: DateTime(2025),
    );

Widget _buildScreen({
  required List<Override> overrides,
}) {
  final router = GoRouter(
    initialLocation: '/profile',
    routes: [
      GoRoute(
        path: '/profile',
        builder: (_, __) => const Scaffold(body: ProfileScreen()),
        routes: [
          GoRoute(
            path: 'rankings',
            builder: (_, __) => const Scaffold(body: Text('RANKINGS_SCREEN')),
          ),
        ],
      ),
    ],
  );

  return ProviderScope(
    overrides: overrides,
    child: MaterialApp.router(
      theme: AppTheme.dark(),
      routerConfig: router,
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      locale: const Locale('es', 'AR'),
    ),
  );
}

void main() {
  final mockUser = MockUser();
  late _FakeRankingOptInController fakeController;

  List<Override> baseOverrides({bool rankingOptIn = false}) {
    fakeController = _FakeRankingOptInController();
    return [
      authNotifierProvider.overrideWith(_StubAuthNotifier.new),
      authStateChangesProvider.overrideWith((_) => Stream.value(mockUser)),
      userProfileProvider.overrideWith((_) => Stream.value(_testProfile())),
      pendingRequestCountProvider(_uid).overrideWith((_) => 0),
      pendingRequestsStreamProvider(_uid).overrideWith((_) => Stream.value([])),
      userSessionStatsProvider.overrideWith((_) async => const UserSessionStats(
          totalSessions: 0, totalVolumeKg: 0, streak: 0)),
      userPublicProfileProvider(_uid).overrideWith(
        (_) => Stream.value(
          UserPublicProfile(uid: _uid, rankingOptIn: rankingOptIn),
        ),
      ),
      rankingOptInControllerProvider.overrideWithValue(fakeController),
    ];
  }

  testWidgets(
      'ProfileScreen does NOT render a Rankings tile in the ENTRENAMIENTO section',
      (tester) async {
    await tester.pumpWidget(_buildScreen(overrides: baseOverrides()));
    await tester.pumpAndSettle();

    expect(find.text('Rankings'), findsNothing);
  });

  testWidgets('ProfileScreen does NOT render the rankingOptIn Switch anywhere',
      (tester) async {
    await tester.pumpWidget(
      _buildScreen(overrides: baseOverrides(rankingOptIn: true)),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('profile_ranking_optin_switch')), findsNothing);
    expect(
        find.byKey(const Key('profile_ranking_optin_loading')), findsNothing);
  });

  testWidgets(
      'ProfileScreen never calls enableRankingOptIn/disableRankingOptIn '
      '(no toggle wired anywhere on the screen)', (tester) async {
    await tester.pumpWidget(_buildScreen(overrides: baseOverrides()));
    await tester.pumpAndSettle();

    expect(fakeController.enabledCalls, isEmpty);
    expect(fakeController.disabledCalls, isEmpty);
  });

  testWidgets(
      'other ENTRENAMIENTO tiles (Mis ejercicios) remain unaffected by the '
      'rankings tile removal', (tester) async {
    await tester.pumpWidget(_buildScreen(overrides: baseOverrides()));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('Mis ejercicios'), 50);
    expect(find.text('Mis ejercicios'), findsOneWidget);
  });
}
