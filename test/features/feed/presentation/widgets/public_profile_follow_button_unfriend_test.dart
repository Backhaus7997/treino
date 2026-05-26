import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/feed/domain/friendship.dart';
import 'package:treino/features/feed/domain/friendship_status.dart';
import 'package:treino/features/feed/presentation/widgets/public_profile_follow_button.dart';
import 'package:treino/features/feed/presentation/widgets/unfriend_confirmation_sheet.dart';
import 'package:treino/features/profile/application/user_providers.dart'
    show firestoreProvider;
import 'package:treino/features/profile/application/user_public_profile_providers.dart';
import 'package:treino/features/profile/domain/user_public_profile.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Friendship _accepted({
  String viewerUid = 'viewer',
  String targetUid = 'target',
}) =>
    Friendship(
      id: Friendship.sortedDocId(viewerUid, targetUid),
      uidA: viewerUid.compareTo(targetUid) <= 0 ? viewerUid : targetUid,
      uidB: viewerUid.compareTo(targetUid) <= 0 ? targetUid : viewerUid,
      status: FriendshipStatus.accepted,
      requesterId: viewerUid,
      members: [viewerUid, targetUid],
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
// Tests: SCENARIO-469, SCENARIO-471 wiring
// ---------------------------------------------------------------------------

void main() {
  group('PublicProfileFollowButton SIGUIENDO upgrade', () {
    // SCENARIO-469: SIGUIENDO pill has a non-null onTap when status=accepted
    // This verifies the GestureDetector wrapping the pill has a real callback.
    // The previous implementation had onTap: null (const _FollowPill).
    testWidgets(
        'SCENARIO-469: SIGUIENDO pill is tappable (tap does not throw and sheet opens)',
        (tester) async {
      final firestore = FakeFirebaseFirestore();
      final friendship = _accepted();

      await tester.pumpWidget(
        _wrap(
          PublicProfileFollowButton(
            friendship: friendship,
            viewerUid: 'viewer',
            targetUid: 'target',
          ),
          firestore,
          extraOverrides: [
            userPublicProfileProvider('target').overrideWith(
              (_) => Stream.value(const UserPublicProfile(
                uid: 'target',
                displayName: 'Vicente',
              )),
            ),
          ],
        ),
      );

      await tester.pump();

      expect(find.text('SIGUIENDO'), findsOneWidget);

      // Tap the SIGUIENDO pill — should open the sheet (not be a no-op)
      await tester.tap(find.text('SIGUIENDO'));
      await tester.pumpAndSettle();

      // The confirmation sheet must be open
      expect(find.byType(UnfriendConfirmationSheet), findsOneWidget);
    });

    // SCENARIO-471 wiring: tapping ELIMINAR in the sheet calls repo.delete
    // and invalidates friendshipByPairProvider so the button transitions to SEGUIR.
    testWidgets(
        'SCENARIO-471 wiring: tapping ELIMINAR calls repo.delete and friendship doc is removed',
        (tester) async {
      final firestore = FakeFirebaseFirestore();
      final friendship = _accepted();

      // Seed the doc in FakeFirestore so delete has something to remove
      await firestore
          .collection('friendships')
          .doc(friendship.id)
          .set({...friendship.toJson(), 'createdAt': Timestamp.now()});

      await tester.pumpWidget(
        _wrap(
          PublicProfileFollowButton(
            friendship: friendship,
            viewerUid: 'viewer',
            targetUid: 'target',
          ),
          firestore,
          extraOverrides: [
            userPublicProfileProvider('target').overrideWith(
              (_) => Stream.value(const UserPublicProfile(
                uid: 'target',
                displayName: 'Vicente',
              )),
            ),
          ],
        ),
      );

      await tester.pump();

      // Open the confirmation sheet
      await tester.tap(find.text('SIGUIENDO'));
      await tester.pumpAndSettle();

      expect(find.byType(UnfriendConfirmationSheet), findsOneWidget);

      // Confirm the unfriend
      await tester.tap(find.text('ELIMINAR'));
      await tester.pumpAndSettle();

      // Sheet dismissed
      expect(find.byType(UnfriendConfirmationSheet), findsNothing);

      // Firestore doc is deleted
      final snap =
          await firestore.collection('friendships').doc(friendship.id).get();
      expect(snap.exists, isFalse);
    });
  });
}
