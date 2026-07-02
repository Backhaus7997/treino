// Phase 4 RED — SCENARIO-RANK-8
//
// ProfileScreen (athlete) exposes a "RANKINGS" entry point in the
// ENTRENAMIENTO section that (a) navigates to /profile/rankings on tap, and
// (b) shows the current rankingOptIn state via a trailing Switch that calls
// RankingOptInController.enableRankingOptIn/disableRankingOptIn.
//
// Spec `gym-rankings` — Opt-In Toggle Lifecycle: the toggle lives in the
// profile sub-tree (design `sdd/rankings/design` — Placement).

import 'dart:async';

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

  @override
  Future<void> enableRankingOptIn(String uid) async {
    enabledCalls.add(uid);
  }

  @override
  Future<void> disableRankingOptIn(String uid) async {
    disabledCalls.add(uid);
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

  testWidgets('RANKINGS tile is visible in the ENTRENAMIENTO section',
      (tester) async {
    await tester.pumpWidget(_buildScreen(overrides: baseOverrides()));
    await tester.pumpAndSettle();

    // Tiles are below the fold — scroll to them first (established pattern,
    // see SCENARIO-530/565).
    await tester.scrollUntilVisible(find.text('Rankings'), 50);
    expect(find.text('Rankings'), findsOneWidget);
  });

  testWidgets('tapping the RANKINGS tile navigates to /profile/rankings',
      (tester) async {
    await tester.pumpWidget(_buildScreen(overrides: baseOverrides()));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('Rankings'), 50);
    await tester.tap(find.text('Rankings'));
    await tester.pumpAndSettle();

    expect(find.text('RANKINGS_SCREEN'), findsOneWidget);
  });

  testWidgets('toggle reflects rankingOptIn == false as OFF', (tester) async {
    await tester.pumpWidget(
      _buildScreen(overrides: baseOverrides(rankingOptIn: false)),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
        find.byKey(const Key('profile_ranking_optin_switch')), 50);
    final toggle = tester.widget<Switch>(
      find.byKey(const Key('profile_ranking_optin_switch')),
    );
    expect(toggle.value, isFalse);
  });

  testWidgets('toggle reflects rankingOptIn == true as ON', (tester) async {
    await tester.pumpWidget(
      _buildScreen(overrides: baseOverrides(rankingOptIn: true)),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
        find.byKey(const Key('profile_ranking_optin_switch')), 50);
    final toggle = tester.widget<Switch>(
      find.byKey(const Key('profile_ranking_optin_switch')),
    );
    expect(toggle.value, isTrue);
  });

  testWidgets('flipping the toggle ON calls enableRankingOptIn(uid)',
      (tester) async {
    await tester.pumpWidget(
      _buildScreen(overrides: baseOverrides(rankingOptIn: false)),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
        find.byKey(const Key('profile_ranking_optin_switch')), 50);
    await tester.tap(find.byKey(const Key('profile_ranking_optin_switch')));
    await tester.pump();

    expect(fakeController.enabledCalls, equals([_uid]));
    expect(fakeController.disabledCalls, isEmpty);
  });

  testWidgets('flipping the toggle OFF calls disableRankingOptIn(uid)',
      (tester) async {
    await tester.pumpWidget(
      _buildScreen(overrides: baseOverrides(rankingOptIn: true)),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
        find.byKey(const Key('profile_ranking_optin_switch')), 50);
    await tester.tap(find.byKey(const Key('profile_ranking_optin_switch')));
    await tester.pump();

    expect(fakeController.disabledCalls, equals([_uid]));
    expect(fakeController.enabledCalls, isEmpty);
  });

  testWidgets(
      'toggle shows a loading spinner while the backfill/clear is in flight',
      (tester) async {
    final completer = Completer<void>();
    final asyncController = _FakeRankingOptInControllerAsync(completer.future);

    await tester.pumpWidget(_buildScreen(overrides: [
      authNotifierProvider.overrideWith(_StubAuthNotifier.new),
      authStateChangesProvider.overrideWith((_) => Stream.value(mockUser)),
      userProfileProvider.overrideWith((_) => Stream.value(_testProfile())),
      pendingRequestCountProvider(_uid).overrideWith((_) => 0),
      pendingRequestsStreamProvider(_uid).overrideWith((_) => Stream.value([])),
      userSessionStatsProvider.overrideWith((_) async => const UserSessionStats(
          totalSessions: 0, totalVolumeKg: 0, streak: 0)),
      userPublicProfileProvider(_uid).overrideWith(
        (_) => Stream.value(
          const UserPublicProfile(uid: _uid, rankingOptIn: false),
        ),
      ),
      rankingOptInControllerProvider.overrideWithValue(asyncController),
    ]));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
        find.byKey(const Key('profile_ranking_optin_switch')), 50);
    await tester.tap(find.byKey(const Key('profile_ranking_optin_switch')));
    await tester.pump();

    expect(
        find.byKey(const Key('profile_ranking_optin_loading')), findsOneWidget);

    completer.complete();
    await tester.pumpAndSettle();
  });
}

class _FakeRankingOptInControllerAsync extends RankingOptInControllerBase {
  _FakeRankingOptInControllerAsync(this._future);
  final Future<void> _future;

  @override
  Future<void> enableRankingOptIn(String uid) => _future;

  @override
  Future<void> disableRankingOptIn(String uid) => _future;
}
