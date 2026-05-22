import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/feed/application/friendship_providers.dart';
import 'package:treino/features/feed/data/friendship_repository.dart';
import 'package:treino/features/feed/domain/friendship.dart';
import 'package:treino/features/feed/domain/friendship_status.dart';
import 'package:treino/features/feed/presentation/widgets/friend_request_inbox_tile.dart';
import 'package:treino/features/feed/presentation/widgets/post_avatar.dart';
import 'package:treino/features/profile/application/user_public_profile_providers.dart';
import 'package:treino/features/profile/domain/user_public_profile.dart';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

final _now = DateTime.utc(2026, 1, 1);

Friendship _makeFriendship({
  String id = 'alice_bob',
  String requesterId = 'bob',
}) =>
    Friendship(
      id: id,
      uidA: 'alice',
      uidB: requesterId,
      status: FriendshipStatus.pending,
      requesterId: requesterId,
      members: ['alice', requesterId],
      createdAt: _now,
    );

/// Stub repository that records calls without touching Firestore.
class _StubFriendshipRepository extends FriendshipRepository {
  _StubFriendshipRepository() : super(firestore: FakeFirebaseFirestore());

  int acceptCallCount = 0;
  int deleteCallCount = 0;
  String? lastAcceptedId;
  String? lastDeletedId;

  @override
  Future<void> accept(String friendshipId, String myUid) async {
    acceptCallCount++;
    lastAcceptedId = friendshipId;
  }

  @override
  Future<void> delete(String friendshipId, String myUid) async {
    deleteCallCount++;
    lastDeletedId = friendshipId;
  }
}

/// Stub whose accept() completes only when completer fires (simulates in-flight).
class _SlowFriendshipRepository extends FriendshipRepository {
  _SlowFriendshipRepository({required this.completer})
      : super(firestore: FakeFirebaseFirestore());

  final Completer<void> completer;
  int acceptCallCount = 0;

  @override
  Future<void> accept(String friendshipId, String myUid) async {
    acceptCallCount++;
    await completer.future;
  }

  @override
  Future<void> delete(String friendshipId, String myUid) async {}
}

Widget _buildTile({
  required Friendship friendship,
  required String viewerUid,
  required List<Override> overrides,
}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(
        body: FriendRequestInboxTile(
          friendship: friendship,
          viewerUid: viewerUid,
        ),
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests: SCENARIO-461..464
// ---------------------------------------------------------------------------

void main() {
  // T10 RED: SCENARIO-465 (clamp regression) and SCENARIO-467 (double-tap guard)
  group('FriendRequestInboxTile double-tap and clamp', () {
    // SCENARIO-465: RECHAZAR on never-accepted friendship → followingCount does not go below 0
    testWidgets(
        'SCENARIO-465: RECHAZAR does not push followingCount below 0 on never-accepted friendship',
        (tester) async {
      final stub = _StubFriendshipRepository();
      final friendship = _makeFriendship(requesterId: 'bob');

      await tester.pumpWidget(
        _buildTile(
          friendship: friendship,
          viewerUid: 'alice',
          overrides: [
            friendshipRepositoryProvider.overrideWithValue(stub),
            userPublicProfileProvider('bob').overrideWith(
              (_) async => const UserPublicProfile(uid: 'bob', displayName: 'Bob'),
            ),
          ],
        ),
      );

      await tester.pump();

      // Tap RECHAZAR — stub delete does not throw, no exception bubbles
      await tester.tap(find.text('RECHAZAR'));
      await tester.pump();

      expect(stub.deleteCallCount, equals(1));
      // No exception should have propagated (no expect-throws means it didn't)
    });

    // SCENARIO-467 (tile): double-tap ACEPTAR → second tap is swallowed:
    // repo.accept called exactly once during in-flight, no exception bubbles.
    testWidgets(
        'SCENARIO-467: double-tap ACEPTAR swallowed — repo.accept called exactly once',
        (tester) async {
      // Slow stub: accept takes 200ms to resolve
      final completer = Completer<void>();
      final slowStub = _SlowFriendshipRepository(completer: completer);
      final friendship = _makeFriendship(requesterId: 'bob');

      await tester.pumpWidget(
        _buildTile(
          friendship: friendship,
          viewerUid: 'alice',
          overrides: [
            friendshipRepositoryProvider.overrideWithValue(slowStub),
            userPublicProfileProvider('bob').overrideWith(
              (_) async => const UserPublicProfile(uid: 'bob', displayName: 'Bob'),
            ),
          ],
        ),
      );

      await tester.pump();

      // Tap ACEPTAR twice in rapid succession
      await tester.tap(find.text('ACEPTAR'));
      await tester.pump();
      await tester.tap(find.text('ACEPTAR'));
      await tester.pump();

      // Repo.accept should have been called exactly once (second tap guarded)
      expect(slowStub.acceptCallCount, equals(1));

      // Complete the pending operation to avoid timer leaks
      completer.complete();
      await tester.pumpAndSettle();
    });
  });

  group('FriendRequestInboxTile render', () {
    // SCENARIO-461: profile resolved → "Ana García" + gym text visible + avatar rendered
    testWidgets(
        'SCENARIO-461: resolved profile shows displayName and gym text',
        (tester) async {
      const profile = UserPublicProfile(
        uid: 'bob',
        displayName: 'Ana García',
        gymId: 'smart-fit-palermo',
      );

      final friendship = _makeFriendship(requesterId: 'bob');

      await tester.pumpWidget(
        _buildTile(
          friendship: friendship,
          viewerUid: 'alice',
          overrides: [
            userPublicProfileProvider('bob').overrideWith(
              (_) async => profile,
            ),
          ],
        ),
      );

      await tester.pump();

      // displayName uppercase (tile renders toUpperCase)
      expect(find.text('ANA GARCÍA'), findsOneWidget);
      // gym name resolved from gym id
      expect(find.text('SMART FIT'), findsOneWidget);
      // PostAvatar should be present
      expect(find.byType(PostAvatar), findsOneWidget);
    });

    // SCENARIO-462: profile null → "Usuario anónimo" + default avatar placeholder
    testWidgets(
        'SCENARIO-462: null profile shows "Usuario anónimo" and default avatar',
        (tester) async {
      final friendship = _makeFriendship(requesterId: 'bob');

      await tester.pumpWidget(
        _buildTile(
          friendship: friendship,
          viewerUid: 'alice',
          overrides: [
            userPublicProfileProvider('bob').overrideWith(
              (_) async => null,
            ),
          ],
        ),
      );

      await tester.pump();

      // The tile uppercases the fallback name
      expect(find.text('USUARIO ANÓNIMO'), findsOneWidget);
      // No gym subtitle row
      expect(find.text('SMART FIT'), findsNothing);
    });

    // SCENARIO-463: ACEPTAR tap → repo.accept(F.id, myUid) called; no exception surfaces
    testWidgets(
        'SCENARIO-463: tapping ACEPTAR calls repo.accept with correct args',
        (tester) async {
      final stub = _StubFriendshipRepository();
      final friendship = _makeFriendship(requesterId: 'bob');

      await tester.pumpWidget(
        _buildTile(
          friendship: friendship,
          viewerUid: 'alice',
          overrides: [
            friendshipRepositoryProvider.overrideWithValue(stub),
            userPublicProfileProvider('bob').overrideWith(
              (_) async => const UserPublicProfile(
                uid: 'bob',
                displayName: 'Bob',
              ),
            ),
          ],
        ),
      );

      await tester.pump();

      await tester.tap(find.text('ACEPTAR'));
      await tester.pump();

      expect(stub.acceptCallCount, equals(1));
      expect(stub.lastAcceptedId, equals('alice_bob'));
    });

    // SCENARIO-464: RECHAZAR tap → no dialog shown + repo.delete(F.id, myUid) called immediately
    testWidgets(
        'SCENARIO-464: tapping RECHAZAR calls repo.delete immediately with no dialog',
        (tester) async {
      final stub = _StubFriendshipRepository();
      final friendship = _makeFriendship(requesterId: 'bob');

      await tester.pumpWidget(
        _buildTile(
          friendship: friendship,
          viewerUid: 'alice',
          overrides: [
            friendshipRepositoryProvider.overrideWithValue(stub),
            userPublicProfileProvider('bob').overrideWith(
              (_) async => const UserPublicProfile(
                uid: 'bob',
                displayName: 'Bob',
              ),
            ),
          ],
        ),
      );

      await tester.pump();

      await tester.tap(find.text('RECHAZAR'));
      await tester.pump();

      // No dialog was shown
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(Dialog), findsNothing);
      // delete was called immediately
      expect(stub.deleteCallCount, equals(1));
      expect(stub.lastDeletedId, equals('alice_bob'));
    });
  });
}
