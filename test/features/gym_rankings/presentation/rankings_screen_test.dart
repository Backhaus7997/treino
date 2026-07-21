// Phase 4 RED — SCENARIO-RANK-7
// rankings-v2 Phase 1 RED (tasks 1.7/1.9) — opt-in gate + invitation state.
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
//   - Opt-In Gate on the Rankings Surface: `rankingOptIn != true` renders
//     the invitation state, no leaderboard data; `rankingOptIn == true`
//     renders leaderboards.
//   - No-Gym Precedence Over Opt-In Gate: no-gym guidance wins regardless
//     of rankingOptIn.
//   - Opt-In Toggle Lives on the Rankings Surface: prominent enable CTA in
//     the invitation state, wired to enableRankingOptIn.
// Design: `sdd/rankings-v2/design` — AD-6.

import 'dart:async';

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
import 'package:treino/features/gyms/domain/gym.dart' show kNoGymId;
import 'package:treino/features/profile/application/ranking_optin_controller_provider.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/application/user_public_profile_providers.dart';
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
      bool rankingOptIn = true,
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
          userPublicProfileProvider(_uid).overrideWith(
            (_) => Stream.value(
              UserPublicProfile(uid: _uid, rankingOptIn: rankingOptIn),
            ),
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
          // AD-4 self-heal fires unconditionally via ref.read on first build
          // whenever rankingOptIn == true — default to a no-op fake so tests
          // that don't care about the self-heal itself never touch real
          // Firestore. Tests exercising the CTA path override this again
          // explicitly (spread AFTER baseOverrides() wins).
          rankingOptInControllerProvider
              .overrideWithValue(_FakeRankingOptInController()),
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

    testWidgets(
        'QA-GYM-101: athletes tied on the metric share a rank (1, 1, 3), the '
        'next distinct value skips the tied count', (tester) async {
      await tester.pumpWidget(_buildScreen(
        overrides: baseOverrides(
          streak: [
            _rankedProfile(uid: 'u2', displayName: 'Lu', racha: 12),
            _rankedProfile(uid: 'u3', displayName: 'Coti', racha: 12),
            _rankedProfile(uid: 'u4', displayName: 'Ana', racha: 8),
          ],
        ),
      ));
      await tester.pumpAndSettle();

      // The two athletes tied at 12 both render the rank badge "1"…
      expect(find.text('1'), findsNWidgets(2));
      // …and the third skips to 3 (standard competition ranking), so a rank
      // badge "2" is never rendered — this proves the row actually consumes
      // competitionRanks, not the old index+1.
      expect(find.text('2'), findsNothing);
      expect(find.text('3'), findsOneWidget);
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

    // ────────────────────────────────────────────────────────────────────
    // rankings-v2 Phase 1 (task 1.7) — Opt-In Gate on the Rankings Surface
    // + No-Gym Precedence Over Opt-In Gate.
    // ────────────────────────────────────────────────────────────────────
    group('opt-in gate', () {
      testWidgets(
          'rankingOptIn != true renders the invitation state, no leaderboard '
          'data', (tester) async {
        await tester.pumpWidget(_buildScreen(
          overrides: baseOverrides(rankingOptIn: false),
        ));
        await tester.pumpAndSettle();

        expect(
            find.byKey(const Key('rankings_invitation_state')), findsOneWidget);
        expect(find.byKey(const Key('rankings_section_streak')), findsNothing);
        expect(find.byKey(const Key('rankings_section_volume')), findsNothing);
        expect(find.byKey(const Key('rankings_section_lifts')), findsNothing);
      });

      testWidgets(
          'rankingOptIn == true renders the 3 leaderboards, no invitation '
          'state', (tester) async {
        await tester.pumpWidget(_buildScreen(
          overrides: baseOverrides(rankingOptIn: true),
        ));
        await tester.pumpAndSettle();

        expect(
            find.byKey(const Key('rankings_section_streak')), findsOneWidget);
        expect(
            find.byKey(const Key('rankings_section_volume')), findsOneWidget);
        expect(find.byKey(const Key('rankings_section_lifts')), findsOneWidget);
        expect(
            find.byKey(const Key('rankings_invitation_state')), findsNothing);
      });

      testWidgets(
          'gymId == null renders the no-gym guidance state regardless of '
          'rankingOptIn (both true and false sub-cases), taking precedence '
          'over the invitation state', (tester) async {
        await tester.pumpWidget(_buildScreen(
          overrides: baseOverrides(gymId: null, rankingOptIn: true),
        ));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('rankings_no_gym_state')), findsOneWidget);
        expect(
            find.byKey(const Key('rankings_invitation_state')), findsNothing);
      });

      testWidgets(
          'gymId == kNoGymId renders the no-gym guidance state when opted '
          'out too', (tester) async {
        await tester.pumpWidget(_buildScreen(
          overrides: baseOverrides(gymId: kNoGymId, rankingOptIn: false),
        ));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('rankings_no_gym_state')), findsOneWidget);
        expect(
            find.byKey(const Key('rankings_invitation_state')), findsNothing);
      });

      testWidgets(
          'gymId == null renders the no-gym guidance state when opted out '
          'too', (tester) async {
        await tester.pumpWidget(_buildScreen(
          overrides: baseOverrides(gymId: null, rankingOptIn: false),
        ));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('rankings_no_gym_state')), findsOneWidget);
        expect(
            find.byKey(const Key('rankings_invitation_state')), findsNothing);
      });

      testWidgets(
          'toggling the overridden userPublicProfileProvider value live-'
          'transitions the rendered state without any navigation call',
          (tester) async {
        final controller = StreamController<UserPublicProfile?>();
        addTearDown(controller.close);

        await tester.pumpWidget(_buildScreen(overrides: [
          authStateChangesProvider.overrideWith((_) => Stream.value(mockUser)),
          userProfileProvider.overrideWith(
            (_) => Stream.value(_profile(gymId: _gymId)),
          ),
          userPublicProfileProvider(_uid)
              .overrideWith((_) => controller.stream),
          streakLeaderboardProvider(_gymId).overrideWith((_) async => []),
          volumeLeaderboardProvider(_gymId).overrideWith((_) async => []),
          squatLeaderboardProvider(_gymId).overrideWith((_) async => []),
          benchLeaderboardProvider(_gymId).overrideWith((_) async => []),
          deadliftLeaderboardProvider(_gymId).overrideWith((_) async => []),
          rankingOptInControllerProvider
              .overrideWithValue(_FakeRankingOptInController()),
        ]));

        controller.add(const UserPublicProfile(uid: _uid, rankingOptIn: false));
        await tester.pumpAndSettle();
        expect(
            find.byKey(const Key('rankings_invitation_state')), findsOneWidget);

        // Flip live — no navigation, no route push, same widget tree.
        controller.add(const UserPublicProfile(uid: _uid, rankingOptIn: true));
        await tester.pumpAndSettle();

        expect(
            find.byKey(const Key('rankings_invitation_state')), findsNothing);
        expect(
            find.byKey(const Key('rankings_section_streak')), findsOneWidget);
      });
    });

    // ────────────────────────────────────────────────────────────────────
    // rankings-v2 Phase 1 (task 1.9) — Invitation-state widget: CTA, spinner,
    // error SnackBar, live reactive swap on success.
    // ────────────────────────────────────────────────────────────────────
    group('invitation state widget', () {
      testWidgets(
          'ACTIVAR RANKINGS CTA is visible and wired to enableRankingOptIn',
          (tester) async {
        final fake = _FakeRankingOptInController();
        await tester.pumpWidget(_buildScreen(overrides: [
          ...baseOverrides(rankingOptIn: false),
          rankingOptInControllerProvider.overrideWithValue(fake),
        ]));
        await tester.pumpAndSettle();

        expect(find.text('ACTIVAR RANKINGS'), findsOneWidget);

        await tester.tap(find.text('ACTIVAR RANKINGS'));
        await tester.pump();

        expect(fake.enabledCalls, equals([_uid]));
      });

      testWidgets(
          'tapping the CTA shows the enabling spinner while pending (button '
          'disabled)', (tester) async {
        final completer = Completer<void>();
        final fake =
            _FakeRankingOptInController(onEnable: () => completer.future);
        await tester.pumpWidget(_buildScreen(overrides: [
          ...baseOverrides(rankingOptIn: false),
          rankingOptInControllerProvider.overrideWithValue(fake),
        ]));
        await tester.pumpAndSettle();

        await tester.tap(find.text('ACTIVAR RANKINGS'));
        await tester.pump();

        expect(
            find.byKey(const Key('rankings_optin_enabling')), findsOneWidget);

        // The CTA must be disabled while pending — a second tap (on the
        // still-mounted button, now showing the spinner instead of the
        // label) does not enqueue a second call.
        await tester.tap(find.byType(ElevatedButton), warnIfMissed: false);
        await tester.pump();
        expect(fake.enabledCalls.length, equals(1));

        completer.complete();
        await tester.pumpAndSettle();
      });

      testWidgets(
          'a thrown error surfaces a SnackBar and re-enables the button',
          (tester) async {
        final fake = _FakeRankingOptInController(
          onEnable: () => Future<void>.error(Exception('boom')),
        );
        await tester.pumpWidget(_buildScreen(overrides: [
          ...baseOverrides(rankingOptIn: false),
          rankingOptInControllerProvider.overrideWithValue(fake),
        ]));
        await tester.pumpAndSettle();

        await tester.tap(find.text('ACTIVAR RANKINGS'));
        await tester.pumpAndSettle();

        expect(find.byType(SnackBar), findsOneWidget);
        expect(find.byKey(const Key('rankings_optin_enabling')), findsNothing);
        expect(find.text('ACTIVAR RANKINGS'), findsOneWidget);
      });

      testWidgets(
          'success requires no manual navigation — the overridden provider '
          'value flipping to true re-renders leaderboards on the same '
          'widget tree', (tester) async {
        final controller = StreamController<UserPublicProfile?>();
        addTearDown(controller.close);
        final fake = _FakeRankingOptInController(
          onEnable: () async {
            controller.add(
              const UserPublicProfile(uid: _uid, rankingOptIn: true),
            );
          },
        );

        await tester.pumpWidget(_buildScreen(overrides: [
          authStateChangesProvider.overrideWith((_) => Stream.value(mockUser)),
          userProfileProvider.overrideWith(
            (_) => Stream.value(_profile(gymId: _gymId)),
          ),
          userPublicProfileProvider(_uid)
              .overrideWith((_) => controller.stream),
          streakLeaderboardProvider(_gymId).overrideWith((_) async => []),
          volumeLeaderboardProvider(_gymId).overrideWith((_) async => []),
          squatLeaderboardProvider(_gymId).overrideWith((_) async => []),
          benchLeaderboardProvider(_gymId).overrideWith((_) async => []),
          deadliftLeaderboardProvider(_gymId).overrideWith((_) async => []),
          rankingOptInControllerProvider.overrideWithValue(fake),
        ]));

        controller.add(const UserPublicProfile(uid: _uid, rankingOptIn: false));
        await tester.pumpAndSettle();
        expect(
            find.byKey(const Key('rankings_invitation_state')), findsOneWidget);

        await tester.tap(find.text('ACTIVAR RANKINGS'));
        await tester.pumpAndSettle();

        expect(
            find.byKey(const Key('rankings_invitation_state')), findsNothing);
        expect(
            find.byKey(const Key('rankings_section_streak')), findsOneWidget);
      });
    });
  });

  // ──────────────────────────────────────────────────────────────────────
  // QA-GYM-101 — pure competition-ranking unit tests (no widget pumping).
  // ──────────────────────────────────────────────────────────────────────
  group('competitionRanks (QA-GYM-101)', () {
    test('no ties → sequential 1..n', () {
      expect(competitionRanks([10, 8, 5]), [1, 2, 3]);
    });
    test('tie at the top shares rank 1, next skips to 3', () {
      expect(competitionRanks([12, 12, 8]), [1, 1, 3]);
    });
    test('tie in the middle (standard "1224" ranking)', () {
      expect(competitionRanks([12, 8, 8, 5]), [1, 2, 2, 4]);
    });
    test('triple tie at the top then a distinct value', () {
      expect(competitionRanks([12, 12, 12, 5]), [1, 1, 1, 4]);
    });
    test('everyone tied → all rank 1', () {
      expect(competitionRanks([5, 5, 5]), [1, 1, 1]);
    });
    test('mixed int/double but numerically equal values still tie', () {
      expect(competitionRanks([12, 12.0, 8]), [1, 1, 3]);
    });
    test('single row → [1]', () {
      expect(competitionRanks([7]), [1]);
    });
    test('empty → []', () {
      expect(competitionRanks(<num>[]), <int>[]);
    });
  });
}

class _FakeRankingOptInController implements RankingOptInControllerBase {
  _FakeRankingOptInController({Future<void> Function()? onEnable})
      : _onEnable = onEnable;

  final Future<void> Function()? _onEnable;
  final List<String> enabledCalls = [];
  final List<String> disabledCalls = [];

  @override
  Future<void> enableRankingOptIn(String uid) async {
    enabledCalls.add(uid);
    if (_onEnable != null) await _onEnable();
  }

  @override
  Future<void> disableRankingOptIn(String uid) async {
    disabledCalls.add(uid);
  }

  @override
  Future<void> syncGymIfDesynced(String uid) async {}
}
