import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/auth/application/auth_providers.dart';
import 'package:treino/features/feed/application/follow_providers.dart';
import 'package:treino/features/feed/domain/follow.dart';
import 'package:treino/features/feed/domain/follow_status.dart';
import 'package:treino/features/feed/presentation/friend_requests_inbox_screen.dart';
import 'package:treino/features/feed/presentation/widgets/friend_request_inbox_tile.dart';
import 'package:treino/l10n/app_l10n.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Solicitud RECIBIDA = arista ENTRANTE `{quien pide}_alice`, sin ordenar.
Follow _makeFollow(String requesterId) => Follow(
      id: Follow.edgeId(requesterId, 'alice'),
      followerUid: requesterId,
      followeeUid: 'alice',
      status: FollowStatus.pending,
      members: [requesterId, 'alice'],
      createdAt: DateTime.utc(2026, 1, 1),
    );

Widget _buildScreen({required List<Override> overrides}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      theme: AppTheme.dark(),
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
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
            pendingReceivedStreamProvider('').overrideWith(
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
            pendingReceivedStreamProvider('').overrideWith(
              (_) => Stream.value(<Follow>[]),
            ),
          ],
        ),
      );

      // TreinoStateSwitcher cross-fadea loading→data (AppMotion.base):
      // pumpAndSettle en vez de un pump suelto para dejar que termine.
      await tester.pumpAndSettle();

      expect(find.text('No hay solicitudes pendientes'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(ListView), findsNothing);
    });

    // SCENARIO-459: data with 2 items → exactly 2 FriendRequestInboxTile widgets
    testWidgets(
        'SCENARIO-459: data con 2 solicitudes renderiza exactly 2 FriendRequestInboxTile widgets',
        (tester) async {
      final f1 = _makeFollow('bob');
      final f2 = _makeFollow('charlie');

      await tester.pumpWidget(
        _buildScreen(
          overrides: [
            authStateChangesProvider.overrideWith(
              (_) => Stream.value(null),
            ),
            pendingReceivedStreamProvider('').overrideWith(
              (_) => Stream.value([f1, f2]),
            ),
          ],
        ),
      );

      // TreinoStateSwitcher cross-fadea loading→data (AppMotion.base):
      // pumpAndSettle en vez de un pump suelto para dejar que termine.
      await tester.pumpAndSettle();

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
            pendingReceivedStreamProvider('').overrideWith(
              (_) => Stream<List<Follow>>.error(Exception('Firestore error')),
            ),
          ],
        ),
      );

      // TreinoStateSwitcher cross-fadea loading→error (AppMotion.base):
      // pumpAndSettle en vez de un pump suelto para dejar que termine.
      await tester.pumpAndSettle();

      expect(
        find.text('No pudimos cargar las solicitudes. Intentá de nuevo.'),
        findsOneWidget,
      );
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });
}
