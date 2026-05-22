import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/auth/application/auth_providers.dart';
import 'package:treino/features/feed/application/friendship_providers.dart';
import 'package:treino/features/feed/domain/friendship.dart';
import 'package:treino/features/feed/domain/friendship_status.dart';
import 'package:treino/features/feed/presentation/friend_requests_inbox_screen.dart';
import 'package:treino/features/feed/presentation/widgets/friend_request_inbox_tile.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

final _now = DateTime.utc(2026, 1, 1);

Friendship _makeFriendship(String id, String requesterId) => Friendship(
      id: id,
      uidA: 'alice',
      uidB: requesterId,
      status: FriendshipStatus.pending,
      requesterId: requesterId,
      members: ['alice', requesterId],
      createdAt: _now,
    );

Widget _buildScreen({required List<Override> overrides}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      theme: AppTheme.dark(),
      home: const Scaffold(body: FriendRequestsInboxScreen()),
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests: SCENARIO-457..460
// ---------------------------------------------------------------------------

void main() {
  group('FriendRequestsInboxScreen states', () {
    // SCENARIO-457: loading state → CircularProgressIndicator, no list items
    testWidgets(
        'SCENARIO-457: loading state shows CircularProgressIndicator and no list items',
        (tester) async {
      await tester.pumpWidget(
        _buildScreen(
          overrides: [
            authStateChangesProvider.overrideWith(
              (_) => Stream.value(null),
            ),
            pendingRequestsStreamProvider('').overrideWith(
              (_) => const Stream.empty(),
            ),
          ],
        ),
      );

      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byType(ListView), findsNothing);
    });

    // SCENARIO-458: empty data → "No hay solicitudes pendientes", no spinner
    testWidgets(
        'SCENARIO-458: empty list shows "No hay solicitudes pendientes" text',
        (tester) async {
      await tester.pumpWidget(
        _buildScreen(
          overrides: [
            authStateChangesProvider.overrideWith(
              (_) => Stream.value(null),
            ),
            pendingRequestsStreamProvider('').overrideWith(
              (_) => Stream.value(<Friendship>[]),
            ),
          ],
        ),
      );

      await tester.pump();

      expect(find.text('No hay solicitudes pendientes'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(ListView), findsNothing);
    });

    // SCENARIO-459: data with 2 items → exactly 2 FriendRequestInboxTile widgets
    testWidgets(
        'SCENARIO-459: data with 2 friendships renders exactly 2 FriendRequestInboxTile widgets',
        (tester) async {
      final f1 = _makeFriendship('alice_bob', 'bob');
      final f2 = _makeFriendship('alice_charlie', 'charlie');

      await tester.pumpWidget(
        _buildScreen(
          overrides: [
            authStateChangesProvider.overrideWith(
              (_) => Stream.value(null),
            ),
            pendingRequestsStreamProvider('').overrideWith(
              (_) => Stream.value([f1, f2]),
            ),
          ],
        ),
      );

      await tester.pump();

      expect(find.byType(FriendRequestInboxTile), findsNWidgets(2));
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    // SCENARIO-460: error → fallback message visible, no uncaught exception
    testWidgets(
        'SCENARIO-460: error state shows fallback message, no uncaught exception',
        (tester) async {
      await tester.pumpWidget(
        _buildScreen(
          overrides: [
            authStateChangesProvider.overrideWith(
              (_) => Stream.value(null),
            ),
            pendingRequestsStreamProvider('').overrideWith(
              (_) =>
                  Stream<List<Friendship>>.error(Exception('Firestore error')),
            ),
          ],
        ),
      );

      await tester.pump();

      expect(
        find.text('No pudimos cargar las solicitudes. Intentá de nuevo.'),
        findsOneWidget,
      );
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });
}
