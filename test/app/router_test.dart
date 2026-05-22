import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/router.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/auth/application/auth_providers.dart';
import 'package:treino/features/feed/application/friendship_providers.dart';
import 'package:treino/features/feed/presentation/friend_requests_inbox_screen.dart';
import 'package:treino/features/profile/application/profile_stats_providers.dart';
import 'package:treino/features/profile/domain/user_session_stats.dart';

// ---------------------------------------------------------------------------
// Tests: SCENARIO-468b — route registration in production router
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
}
