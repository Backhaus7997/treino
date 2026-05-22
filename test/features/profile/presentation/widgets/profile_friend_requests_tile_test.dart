import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/auth/application/auth_providers.dart';
import 'package:treino/features/feed/application/friendship_providers.dart';
import 'package:treino/features/profile/presentation/widgets/profile_friend_requests_tile.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Widget _buildTile({
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
              body: ProfileFriendRequestsTile(),
            ),
            routes: [
              GoRoute(
                path: 'friend-requests',
                builder: (_, __) => const Scaffold(body: Text('INBOX')),
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
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests: SCENARIO-465a, SCENARIO-466, SCENARIO-467 (profile tile level)
// ---------------------------------------------------------------------------

void main() {
  group('ProfileFriendRequestsTile', () {
    // SCENARIO-465a: count=3 → tile displays "Solicitudes de amistad (3)"
    testWidgets(
        'SCENARIO-465a: tile displays "Solicitudes de amistad (3)" when count is 3',
        (tester) async {
      await tester.pumpWidget(
        _buildTile(
          overrides: [
            authStateChangesProvider.overrideWith(
              (_) => Stream.value(null),
            ),
            pendingRequestCountProvider('').overrideWith((_) => 3),
          ],
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Solicitudes de amistad (3)'), findsOneWidget);
    });

    // SCENARIO-466: count=0 → tile is visible and displays "Solicitudes de amistad (0)"
    testWidgets(
        'SCENARIO-466: tile is visible and shows "Solicitudes de amistad (0)" when count is 0',
        (tester) async {
      await tester.pumpWidget(
        _buildTile(
          overrides: [
            authStateChangesProvider.overrideWith(
              (_) => Stream.value(null),
            ),
            pendingRequestCountProvider('').overrideWith((_) => 0),
          ],
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Solicitudes de amistad (0)'), findsOneWidget);
    });

    // SCENARIO-467 (tile-level): tap → context.push('/profile/friend-requests') is called
    testWidgets(
        'SCENARIO-467: tapping tile navigates to /profile/friend-requests',
        (tester) async {
      await tester.pumpWidget(
        _buildTile(
          overrides: [
            authStateChangesProvider.overrideWith(
              (_) => Stream.value(null),
            ),
            pendingRequestCountProvider('').overrideWith((_) => 2),
          ],
        ),
      );

      await tester.pumpAndSettle();

      await tester.tap(find.text('Solicitudes de amistad (2)'));
      await tester.pumpAndSettle();

      // The INBOX screen should be visible after navigation
      expect(find.text('INBOX'), findsOneWidget);
    });
  });
}
