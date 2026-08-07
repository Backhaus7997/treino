import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/l10n/app_l10n.dart';
import 'package:treino/features/feed/application/feed_screen_providers.dart'
    show myFollowingFeedProvider;
import 'package:treino/features/feed/application/follow_providers.dart';
import 'package:treino/features/feed/data/follow_repository.dart';
import 'package:treino/features/feed/domain/follow.dart';
import 'package:treino/features/feed/domain/follow_status.dart';
import 'package:treino/features/feed/presentation/widgets/friend_request_inbox_tile.dart';
import 'package:treino/features/feed/presentation/widgets/post_avatar.dart';
import 'package:treino/features/profile/application/user_public_profile_providers.dart';
import 'package:treino/features/profile/domain/user_public_profile.dart';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// La solicitud RECIBIDA por alice es la arista ENTRANTE: `{quien pide}_alice`.
/// El doc id NO se ordena — la dirección ES el documento.
Follow _makeFollow({
  String id = 'bob_alice',
  String requesterId = 'bob',
}) =>
    Follow(
      id: id,
      followerUid: requesterId,
      followeeUid: 'alice',
      status: FollowStatus.pending,
      members: [requesterId, 'alice'],
      createdAt: DateTime.utc(2026, 1, 1),
    );

/// Stub repository that records calls without touching Firestore.
class _StubFollowRepository extends FollowRepository {
  _StubFollowRepository() : super(firestore: FakeFirebaseFirestore());

  int acceptCallCount = 0;
  int deleteCallCount = 0;
  String? lastAcceptedId;
  String? lastDeletedId;

  @override
  Future<void> acceptRequest(String edgeId, String myUid) async {
    acceptCallCount++;
    lastAcceptedId = edgeId;
  }

  @override
  Future<void> deleteEdge(String edgeId) async {
    deleteCallCount++;
    lastDeletedId = edgeId;
  }
}

/// Stub whose accept() completes only when completer fires (simulates in-flight).
class _SlowFollowRepository extends FollowRepository {
  _SlowFollowRepository({required this.completer})
      : super(firestore: FakeFirebaseFirestore());

  final Completer<void> completer;
  int acceptCallCount = 0;

  @override
  Future<void> acceptRequest(String edgeId, String myUid) async {
    acceptCallCount++;
    await completer.future;
  }

  @override
  Future<void> deleteEdge(String edgeId) async {}
}

Widget _buildTile({
  required Follow follow,
  required String viewerUid,
  required List<Override> overrides,
}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      theme: AppTheme.dark(),
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      home: Scaffold(
        body: FriendRequestInboxTile(
          follow: follow,
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
    // SCENARIO-465: RECHAZAR on never-accepted edge → followingCount does not go below 0
    testWidgets(
        'SCENARIO-465: RECHAZAR does not push followingCount below 0 on never-accepted edge',
        (tester) async {
      final stub = _StubFollowRepository();
      final follow = _makeFollow(requesterId: 'bob');

      await tester.pumpWidget(
        _buildTile(
          follow: follow,
          viewerUid: 'alice',
          overrides: [
            followRepositoryProvider.overrideWithValue(stub),
            userPublicProfileProvider('bob').overrideWith(
              (_) => Stream.value(
                  const UserPublicProfile(uid: 'bob', displayName: 'Bob')),
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
      final slowStub = _SlowFollowRepository(completer: completer);
      final follow = _makeFollow(requesterId: 'bob');

      await tester.pumpWidget(
        _buildTile(
          follow: follow,
          viewerUid: 'alice',
          overrides: [
            followRepositoryProvider.overrideWithValue(slowStub),
            userPublicProfileProvider('bob').overrideWith(
              (_) => Stream.value(
                  const UserPublicProfile(uid: 'bob', displayName: 'Bob')),
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
    testWidgets('SCENARIO-461: resolved profile shows displayName and gym text',
        (tester) async {
      const profile = UserPublicProfile(
        uid: 'bob',
        displayName: 'Ana García',
        gymId: 'smart-fit-palermo',
        gymName: 'SmartFit - Palermo',
      );

      final follow = _makeFollow(requesterId: 'bob');

      await tester.pumpWidget(
        _buildTile(
          follow: follow,
          viewerUid: 'alice',
          overrides: [
            userPublicProfileProvider('bob').overrideWith(
              (_) => Stream.value(profile),
            ),
          ],
        ),
      );

      await tester.pump();

      // displayName uppercase (tile renders toUpperCase)
      expect(find.text('ANA GARCÍA'), findsOneWidget);
      // gym name read from the denormalized profile.gymName field
      expect(find.text('SmartFit - Palermo'), findsOneWidget);
      // PostAvatar should be present
      expect(find.byType(PostAvatar), findsOneWidget);
    });

    // SCENARIO-462: profile null → "Usuario anónimo" + default avatar placeholder
    testWidgets(
        'SCENARIO-462: null profile shows "Usuario anónimo" and default avatar',
        (tester) async {
      final follow = _makeFollow(requesterId: 'bob');

      await tester.pumpWidget(
        _buildTile(
          follow: follow,
          viewerUid: 'alice',
          overrides: [
            userPublicProfileProvider('bob').overrideWith(
              (_) => Stream.value(null),
            ),
          ],
        ),
      );

      await tester.pump();

      // The tile uppercases the fallback name
      expect(find.text('USUARIO ANÓNIMO'), findsOneWidget);
      // No gym subtitle row
      expect(find.text('SmartFit - Palermo'), findsNothing);
    });

    // SCENARIO-463: ACEPTAR tap → repo.accept(F.id, myUid) called; no exception surfaces
    testWidgets(
        'SCENARIO-463: tapping ACEPTAR calls repo.accept with correct args',
        (tester) async {
      final stub = _StubFollowRepository();
      final follow = _makeFollow(requesterId: 'bob');

      await tester.pumpWidget(
        _buildTile(
          follow: follow,
          viewerUid: 'alice',
          overrides: [
            followRepositoryProvider.overrideWithValue(stub),
            userPublicProfileProvider('bob').overrideWith(
              (_) => Stream.value(const UserPublicProfile(
                uid: 'bob',
                displayName: 'Bob',
              )),
            ),
          ],
        ),
      );

      await tester.pump();

      await tester.tap(find.text('ACEPTAR'));
      await tester.pump();

      expect(stub.acceptCallCount, equals(1));
      // 'bob_alice', NO 'alice_bob': el doc id de `follows` NO se ordena. Bob
      // sigue a alice, así que la arista es {bob}_{alice}. El id ordenado del
      // modelo viejo apuntaría al documento equivocado — o, peor, al de la
      // dirección contraria.
      expect(stub.lastAcceptedId, equals('bob_alice'));
    });

    // SCENARIO-464: RECHAZAR tap → no dialog shown + repo.delete(F.id, myUid) called immediately
    testWidgets(
        'SCENARIO-464: tapping RECHAZAR calls repo.delete immediately with no dialog',
        (tester) async {
      final stub = _StubFollowRepository();
      final follow = _makeFollow(requesterId: 'bob');

      await tester.pumpWidget(
        _buildTile(
          follow: follow,
          viewerUid: 'alice',
          overrides: [
            followRepositoryProvider.overrideWithValue(stub),
            userPublicProfileProvider('bob').overrideWith(
              (_) => Stream.value(const UserPublicProfile(
                uid: 'bob',
                displayName: 'Bob',
              )),
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
      // Rechazar borra la MISMA arista entrante que se habría aceptado, y
      // nunca la inversa: si alice sigue a bob, eso queda intacto.
      expect(stub.lastDeletedId, equals('bob_alice'));
    });
  });

  // ---------------------------------------------------------------------------
  // SCENARIO-472: Tappable requester zone navigates; action pills do NOT
  // ---------------------------------------------------------------------------

  group('FriendRequestInboxTile tappable requester zone (SCENARIO-472)', () {
    // Builds the tile inside a GoRouter so we can detect navigation
    Widget buildTileWithRouter({
      required Follow follow,
      required String viewerUid,
      required List<Override> overrides,
      required List<String> navigatedRoutes,
    }) {
      final router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => Scaffold(
              body: FriendRequestInboxTile(
                follow: follow,
                viewerUid: viewerUid,
              ),
            ),
          ),
          GoRoute(
            path: '/feed/profile/:uid',
            builder: (context, state) {
              final uid = state.pathParameters['uid']!;
              navigatedRoutes.add('/feed/profile/$uid');
              return Scaffold(body: Text('Profile $uid'));
            },
          ),
        ],
      );

      return ProviderScope(
        overrides: overrides,
        child: MaterialApp.router(
          theme: AppTheme.dark(),
          localizationsDelegates: AppL10n.localizationsDelegates,
          supportedLocales: AppL10n.supportedLocales,
          routerConfig: router,
        ),
      );
    }

    // SCENARIO-472: tap requester zone → navigates to /feed/profile/{requesterUid}
    testWidgets(
        'SCENARIO-472: tapping avatar/name zone navigates to /feed/profile/requesterUid',
        (tester) async {
      final navigatedRoutes = <String>[];
      final follow = _makeFollow(requesterId: 'vicente-uid');

      await tester.pumpWidget(
        buildTileWithRouter(
          follow: follow,
          viewerUid: 'alice',
          overrides: [
            userPublicProfileProvider('vicente-uid').overrideWith(
              (_) => Stream.value(const UserPublicProfile(
                uid: 'vicente-uid',
                displayName: 'Vicente',
              )),
            ),
          ],
          navigatedRoutes: navigatedRoutes,
        ),
      );

      await tester.pump();

      // Tap on the PostAvatar (part of the tappable zone)
      await tester.tap(find.byType(PostAvatar));
      await tester.pumpAndSettle();

      expect(navigatedRoutes, contains('/feed/profile/vicente-uid'));
    });

    // SCENARIO-472: tapping ACEPTAR does NOT navigate
    testWidgets(
        'SCENARIO-472: tapping ACEPTAR does NOT navigate to the public profile route',
        (tester) async {
      final navigatedRoutes = <String>[];
      final stub = _StubFollowRepository();
      final follow = _makeFollow(requesterId: 'vicente-uid');

      await tester.pumpWidget(
        buildTileWithRouter(
          follow: follow,
          viewerUid: 'alice',
          overrides: [
            followRepositoryProvider.overrideWithValue(stub),
            userPublicProfileProvider('vicente-uid').overrideWith(
              (_) => Stream.value(const UserPublicProfile(
                uid: 'vicente-uid',
                displayName: 'Vicente',
              )),
            ),
          ],
          navigatedRoutes: navigatedRoutes,
        ),
      );

      await tester.pump();

      await tester.tap(find.text('ACEPTAR'));
      await tester.pumpAndSettle();

      // No navigation to profile
      expect(navigatedRoutes, isEmpty);
      // But the repo call was made
      expect(stub.acceptCallCount, equals(1));
    });

    // SCENARIO-472: tapping RECHAZAR does NOT navigate
    testWidgets(
        'SCENARIO-472: tapping RECHAZAR does NOT navigate to the public profile route',
        (tester) async {
      final navigatedRoutes = <String>[];
      final stub = _StubFollowRepository();
      final follow = _makeFollow(requesterId: 'vicente-uid');

      await tester.pumpWidget(
        buildTileWithRouter(
          follow: follow,
          viewerUid: 'alice',
          overrides: [
            followRepositoryProvider.overrideWithValue(stub),
            userPublicProfileProvider('vicente-uid').overrideWith(
              (_) => Stream.value(const UserPublicProfile(
                uid: 'vicente-uid',
                displayName: 'Vicente',
              )),
            ),
          ],
          navigatedRoutes: navigatedRoutes,
        ),
      );

      await tester.pump();

      await tester.tap(find.text('RECHAZAR'));
      await tester.pumpAndSettle();

      // No navigation to profile
      expect(navigatedRoutes, isEmpty);
      // But the repo call was made
      expect(stub.deleteCallCount, equals(1));
    });
  });

  // ---------------------------------------------------------------------------
  // SCENARIO-493: _onAceptar invalidation cleanup (T20 RED / T21 GREEN)
  // ---------------------------------------------------------------------------
  group('FriendRequestInboxTile._onAceptar invalidation (SCENARIO-493)', () {
    // SCENARIO-493: _onAceptar DOES call container.invalidate(myFollowingFeedProvider)
    // AND does NOT call container.invalidate for the converted stream providers.
    testWidgets(
        'SCENARIO-493: _onAceptar invalidates myFollowingFeedProvider but NOT followingProvider or followEdgeProvider',
        (tester) async {
      final stub = _StubFollowRepository();
      final follow = _makeFollow(requesterId: 'bob');
      var myFollowingFeedBuildCount = 0;

      // Build with an active listener on myFollowingFeedProvider.
      // The tile uses ProviderScope.containerOf(context) which resolves to
      // the root ProviderScope — so myFollowingFeedProvider must be in the
      // same scope for container.invalidate(myFollowingFeedProvider) to trigger a rebuild.
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            followRepositoryProvider.overrideWithValue(stub),
            userPublicProfileProvider('bob').overrideWith(
              (_) => Stream.value(const UserPublicProfile(
                uid: 'bob',
                displayName: 'Bob',
              )),
            ),
            myFollowingFeedProvider.overrideWith((ref) async {
              myFollowingFeedBuildCount++;
              return const [];
            }),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            localizationsDelegates: AppL10n.localizationsDelegates,
            supportedLocales: AppL10n.supportedLocales,
            home: Scaffold(
              body: Column(
                children: [
                  // Active consumer ensures invalidation triggers rebuild
                  Consumer(
                    builder: (_, ref, __) {
                      ref.watch(myFollowingFeedProvider);
                      return const SizedBox.shrink();
                    },
                  ),
                  FriendRequestInboxTile(
                    follow: follow,
                    viewerUid: 'alice',
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      final countBeforeTap = myFollowingFeedBuildCount;
      expect(countBeforeTap, greaterThan(0),
          reason: 'Provider should build at least once on render');

      await tester.tap(find.text('ACEPTAR'));
      await tester.pump();

      // repo.accept was called
      expect(stub.acceptCallCount, equals(1));

      // myFollowingFeedProvider should have been invalidated → rebuilt
      expect(
        myFollowingFeedBuildCount,
        greaterThan(countBeforeTap),
        reason:
            '_onAceptar must call container.invalidate(myFollowingFeedProvider)',
      );
    });
  });
}
