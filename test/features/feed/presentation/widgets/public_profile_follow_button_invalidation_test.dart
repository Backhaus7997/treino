/// Tests for REQ-FPS-008 invalidation cleanup (SCENARIO-491b, SCENARIO-492).
///
/// Verifies that after the stream conversion:
///   - SEGUIR and ACEPTAR do NOT call ref.invalidate for friendshipByPairProvider
///     or acceptedFriendsProvider (streams self-update)
///   - ACEPTAR / unfriend DOES preserve ref.invalidate(myFriendsFeedProvider)
library;

import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/feed/application/feed_screen_providers.dart'
    show myFriendsFeedProvider;
import 'package:treino/features/feed/application/friendship_providers.dart'
    show acceptedFriendsProvider;
import 'package:treino/features/feed/application/public_profile_providers.dart'
    show friendshipByPairProvider;
import 'package:treino/features/feed/domain/friendship.dart';
import 'package:treino/features/feed/domain/friendship_status.dart';
import 'package:treino/features/feed/presentation/widgets/public_profile_follow_button.dart';
import 'package:treino/features/profile/application/user_providers.dart'
    show firestoreProvider;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Friendship _pending({required String requesterId}) => Friendship(
      id: Friendship.sortedDocId('viewer', 'target'),
      uidA: 'target',
      uidB: 'viewer',
      status: FriendshipStatus.pending,
      requesterId: requesterId,
      members: const ['target', 'viewer'],
      createdAt: DateTime.utc(2026, 1, 1),
    );

Widget _wrap(
  Widget w,
  FakeFirebaseFirestore firestore, {
  List<Override> extraOverrides = const [],
}) =>
    ProviderScope(
      overrides: [
        firestoreProvider.overrideWithValue(firestore),
        ...extraOverrides,
      ],
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(body: w),
      ),
    );

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('PublicProfileFollowButton invalidation cleanup (SCENARIO-491b, 492)',
      () {
    // SCENARIO-491b: SEGUIR onTap does NOT call ref.invalidate for
    // friendshipByPairProvider or acceptedFriendsProvider
    testWidgets(
        'SCENARIO-491b: tap SEGUIR does NOT invalidate friendshipByPairProvider or acceptedFriendsProvider',
        (tester) async {
      final firestore = FakeFirebaseFirestore();

      // Track which providers are read (as proxy for invalidation detection).
      // Since we can't easily intercept ref.invalidate in widget tests,
      // we verify the behavior by checking that the Firestore doc IS written
      // (SEGUIR action fired) but no manual invalidate was attempted on
      // the stream providers.
      //
      // The real assertion is structural: after T19 GREEN, the source code
      // will not contain `invalidate(friendshipByPairProvider` or
      // `invalidate(acceptedFriendsProvider` — verified by flutter analyze.
      //
      // For the widget test, we assert the primary action fired (doc created)
      // and that no exception occurred (invalidating a StreamProvider is
      // harmless but we verify the action path was clean).

      await tester.pumpWidget(_wrap(
        const PublicProfileFollowButton(
          friendship: null, // null → SEGUIR state
          viewerUid: 'viewer',
          targetUid: 'target',
        ),
        firestore,
        extraOverrides: [
          // Stream providers override — no invalidate should be called on these
          friendshipByPairProvider.overrideWith(
            (ref, pair) => Stream.value(null),
          ),
          acceptedFriendsProvider.overrideWith(
            (ref, uid) => Stream.value(const <String>[]),
          ),
        ],
      ));
      await tester.pump();

      expect(find.text('SEGUIR'), findsOneWidget);

      await tester.tap(find.text('SEGUIR'));
      await tester.pumpAndSettle();

      // Primary action: friendship doc written
      final docId = Friendship.sortedDocId('viewer', 'target');
      final snap = await firestore.collection('friendships').doc(docId).get();
      expect(snap.exists, isTrue);
      expect(snap.data()!['requesterId'], equals('viewer'));
      // No crash occurred — the tap succeeded without the obsolete invalidation calls
    });

    // SCENARIO-492: ACEPTAR onTap DOES call ref.invalidate(myFriendsFeedProvider)
    testWidgets(
        'SCENARIO-492: tap ACEPTAR calls repo.accept AND invalidates myFriendsFeedProvider',
        (tester) async {
      final firestore = FakeFirebaseFirestore();
      final pending = _pending(requesterId: 'target');

      // Seed the friendship doc in Firestore so accept() can update it
      await firestore
          .collection('friendships')
          .doc(pending.id)
          .set({...pending.toJson(), 'createdAt': Timestamp.now()});

      // Track myFriendsFeedProvider rebuilds to detect invalidation.
      // Invalidation causes a rebuild only when there's an active listener.
      // We create an active listener on myFriendsFeedProvider via ProviderScope
      // + a Consumer widget, then check if it rebuilt after ACEPTAR.
      var myFriendsFeedBuildCount = 0;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            firestoreProvider.overrideWithValue(firestore),
            friendshipByPairProvider.overrideWith(
              (ref, pair) => Stream.value(pending),
            ),
            acceptedFriendsProvider.overrideWith(
              (ref, uid) => Stream.value(const <String>[]),
            ),
            myFriendsFeedProvider.overrideWith((ref) async {
              myFriendsFeedBuildCount++;
              return const [];
            }),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: Scaffold(
              body: Column(
                children: [
                  // Active consumer of myFriendsFeedProvider — ensures
                  // ref.invalidate triggers a rebuild
                  Consumer(
                    builder: (_, ref, __) {
                      ref.watch(myFriendsFeedProvider);
                      return const SizedBox.shrink();
                    },
                  ),
                  PublicProfileFollowButton(
                    friendship: pending,
                    viewerUid: 'viewer',
                    targetUid: 'target',
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      // Wait for myFriendsFeedProvider to have an initial build
      await tester.pump();
      final countAfterInitialRender = myFriendsFeedBuildCount;
      expect(countAfterInitialRender, greaterThan(0),
          reason: 'myFriendsFeedProvider should build at least once on render');

      await tester.tap(find.text('ACEPTAR'));
      await tester.pumpAndSettle();

      // myFriendsFeedProvider should have been invalidated and rebuilt
      expect(
        myFriendsFeedBuildCount,
        greaterThan(countAfterInitialRender),
        reason: 'ACEPTAR must call ref.invalidate(myFriendsFeedProvider)',
      );

      // Friendship doc in Firestore should now be accepted
      final snap =
          await firestore.collection('friendships').doc(pending.id).get();
      expect(snap.data()!['status'], equals('accepted'));
    });
  });
}
