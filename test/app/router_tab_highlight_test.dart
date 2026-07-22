// Issue #387 — the highlighted bottom-bar tab must keep the ORIGIN branch
// when a screen shared across branches is opened from another tab.
//
// _ShellScaffold derives the active tab from the location's path prefix, so
// the fix registers ORIGIN-branch mirrors of the shared screens:
//   - /feed/friend-requests    (twin of /profile/friend-requests) — feed bell
//   - /profile/availability-editor (twin of /coach/availability-editor) —
//     TrainerProfileView "Disponibilidad" row
// Same route-mirroring pattern as the coach plan/exercise routes (issue #410).
//
// Auth note: authNotifierProvider is overridden to stay AsyncLoading forever,
// so authRedirect returns null (stay) on EVERY navigation. The existing
// router_test.dart pattern (navigate once while auth resolves) only survives
// a single navigation; these tests push and pop after settling.

import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:treino/app/router.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/widgets/treino_bottom_bar.dart';
import 'package:treino/features/auth/application/auth_notifier.dart';
import 'package:treino/features/auth/application/auth_providers.dart';
import 'package:treino/features/coach/application/agenda_providers.dart';
import 'package:treino/features/coach/domain/availability_override.dart';
import 'package:treino/features/coach/domain/availability_rule.dart';
import 'package:treino/features/coach/presentation/availability_editor_screen.dart';
import 'package:treino/features/feed/application/feed_screen_providers.dart';
import 'package:treino/features/feed/application/friendship_providers.dart';
import 'package:treino/features/feed/application/post_providers.dart';
import 'package:treino/features/feed/domain/feed_segment.dart';
import 'package:treino/features/feed/domain/post.dart';
import 'package:treino/features/feed/feed_screen.dart';
import 'package:treino/features/feed/presentation/friend_requests_inbox_screen.dart';
import 'package:treino/features/profile/application/profile_stats_providers.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';
import 'package:treino/features/profile/domain/user_session_stats.dart';
import 'package:treino/features/profile/profile_screen.dart';
import 'package:treino/l10n/app_l10n.dart';

// ---------------------------------------------------------------------------
// Shared test scaffolding
// ---------------------------------------------------------------------------

/// Never resolves → authRedirect sees AsyncLoading on every evaluation and
/// returns null, so imperative push/pop across branches is never redirected.
class _LoadingAuthNotifier extends AuthNotifier {
  @override
  Future<User?> build() => Completer<User?>().future;
}

UserProfile _testProfile() => UserProfile(
      uid: 'uid-test',
      email: 'test@test.com',
      displayName: 'Test User',
      role: UserRole.athlete,
      createdAt: DateTime(2025),
      updatedAt: DateTime(2025),
    );

List<Override> _overrides() => [
      authStateChangesProvider.overrideWith((_) => const Stream<User?>.empty()),
      authNotifierProvider.overrideWith(_LoadingAuthNotifier.new),
      userProfileProvider.overrideWith((_) => Stream.value(_testProfile())),
      userSessionStatsProvider.overrideWith(
        (_) async => const UserSessionStats(
            totalSessions: 0, totalVolumeKg: 0, streak: 0),
      ),
      pendingRequestCountProvider('').overrideWith((_) => 0),
      pendingRequestsStreamProvider('').overrideWith((_) => Stream.value([])),
      // Feed tab root (origin of the Solicitudes push).
      feedSegmentProvider.overrideWith((ref) => FeedSegment.amigos),
      myFriendsFeedProvider.overrideWith((ref) async => const <Post>[]),
      myGymFeedProvider.overrideWith((ref) async => null),
      feedPublicProvider.overrideWith((ref) async => const <Post>[]),
      // Availability editor streams (trainerId travels as a query param).
      availabilityRulesStreamProvider('trainer-1').overrideWith(
        (ref) => Stream.value(const <AvailabilityRule>[]),
      ),
      overridesStreamProvider(OverridesKey(
        trainerId: 'trainer-1',
        fromDate: DateTime.utc(2026, 1, 1),
        toDate: DateTime.utc(2027, 12, 31),
      )).overrideWith((ref) => Stream.value(const <AvailabilityOverride>[])),
    ];

Future<GoRouter> _pumpRouter(
    WidgetTester tester, String initialLocation) async {
  final container = ProviderContainer(overrides: _overrides());
  addTearDown(container.dispose);
  final router = buildRouter(
    refreshListenable: ValueNotifier<int>(0),
    read: container.read,
  );
  router.go(initialLocation);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        theme: AppTheme.dark(),
        routerConfig: router,
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        locale: const Locale('es', 'AR'),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

/// Index the shell's bottom bar is highlighting: 0 workout · 1 feed · 2 home ·
/// 3 coach · 4 profile (mirrors _kTabs in lib/app/router.dart).
int _tabIndex(WidgetTester tester) =>
    tester.widget<TreinoBottomBar>(find.byType(TreinoBottomBar)).currentIndex;

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('Router — origin-branch tab highlight (#387)', () {
    testWidgets(
        'FEED → Solicitudes keeps FEED highlighted and pops back to /feed',
        (tester) async {
      final router = await _pumpRouter(tester, '/feed');
      expect(_tabIndex(tester), 1, reason: 'sanity: /feed highlights FEED');

      // Same push the feed header bell performs.
      router.push('/feed/friend-requests');
      await tester.pumpAndSettle();

      expect(find.byType(FriendRequestsInboxScreen), findsOneWidget);
      expect(_tabIndex(tester), 1,
          reason: 'inbox opened from FEED must keep FEED highlighted, '
              'not jump to PERFIL');

      router.pop();
      await tester.pumpAndSettle();

      expect(find.byType(FeedScreen), findsOneWidget);
      expect(_tabIndex(tester), 1,
          reason: 'back must land on the FEED tab root');
    });

    testWidgets(
        'PERFIL → Mis horarios keeps PERFIL highlighted and pops back to /profile',
        (tester) async {
      final router = await _pumpRouter(tester, '/profile');
      expect(_tabIndex(tester), 4,
          reason: 'sanity: /profile highlights PERFIL');

      // Same push TrainerProfileView's "Disponibilidad" row performs.
      router.push('/profile/availability-editor?trainerId=trainer-1');
      await tester.pumpAndSettle();

      expect(find.byType(AvailabilityEditorScreen), findsOneWidget);
      expect(_tabIndex(tester), 4,
          reason: 'editor opened from PERFIL must keep PERFIL highlighted, '
              'not jump to COACH');

      router.pop();
      await tester.pumpAndSettle();

      expect(find.byType(ProfileScreen), findsOneWidget);
      expect(_tabIndex(tester), 4,
          reason: 'back must land on the PERFIL tab root');
    });

    testWidgets(
        'twin /coach/availability-editor still highlights COACH '
        '(TrainerAgendaTab origin)', (tester) async {
      await _pumpRouter(
          tester, '/coach/availability-editor?trainerId=trainer-1');

      expect(find.byType(AvailabilityEditorScreen), findsOneWidget);
      expect(_tabIndex(tester), 3);
    });

    testWidgets(
        'twin /profile/friend-requests still highlights PERFIL '
        '(ProfileScreen Solicitudes origin)', (tester) async {
      await _pumpRouter(tester, '/profile/friend-requests');

      expect(find.byType(FriendRequestsInboxScreen), findsOneWidget);
      expect(_tabIndex(tester), 4);
    });
  });
}
