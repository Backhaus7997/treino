import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/feed/application/friendship_providers.dart'
    show friendshipRepositoryProvider;
import 'package:treino/features/feed/data/friendship_repository.dart';
import 'package:treino/features/feed/domain/friendship.dart';
import 'package:treino/features/feed/domain/friendship_status.dart';
import 'package:treino/features/feed/presentation/widgets/public_profile_follow_button.dart';
import 'package:treino/l10n/app_l10n.dart';

/// Repository whose write paths always throw, simulating an offline /
/// permission-denied Firestore write (the bug repro).
class _ThrowingFriendshipRepository extends FriendshipRepository {
  _ThrowingFriendshipRepository() : super(firestore: FakeFirebaseFirestore());

  @override
  Future<Friendship> request(String myUid, String otherUid) async {
    throw StateError('write failed');
  }

  @override
  Future<void> accept(String friendshipId, String myUid) async {
    throw StateError('write failed');
  }
}

Widget _wrap(Widget w, FriendshipRepository repo) => ProviderScope(
      overrides: [
        friendshipRepositoryProvider.overrideWithValue(repo),
      ],
      child: MaterialApp(
        theme: AppTheme.dark(),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        home: Scaffold(body: w),
      ),
    );

Friendship _pending({required String requesterId}) => Friendship(
      id: Friendship.sortedDocId('viewer', 'target'),
      uidA: 'target',
      uidB: 'viewer',
      status: FriendshipStatus.pending,
      requesterId: requesterId,
      members: const ['target', 'viewer'],
      createdAt: DateTime.utc(2026, 1, 1),
    );

void main() {
  group('PublicProfileFollowButton error handling', () {
    testWidgets(
        'tapping SEGUIR swallows a failing request — no uncaught async error',
        (tester) async {
      final repo = _ThrowingFriendshipRepository();
      await tester.pumpWidget(_wrap(
        const PublicProfileFollowButton(
          friendship: null,
          viewerUid: 'viewer',
          targetUid: 'target',
        ),
        repo,
      ));
      await tester.pump();

      await tester.tap(find.text('SEGUIR'));
      await tester.pumpAndSettle();

      // Before the fix the StateError escaped the async GestureDetector
      // callback as an unhandled error and would surface here.
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'tapping ACEPTAR swallows a failing accept — no uncaught async error',
        (tester) async {
      final repo = _ThrowingFriendshipRepository();
      await tester.pumpWidget(_wrap(
        PublicProfileFollowButton(
          friendship: _pending(requesterId: 'target'),
          viewerUid: 'viewer',
          targetUid: 'target',
        ),
        repo,
      ));
      await tester.pump();

      await tester.tap(find.text('ACEPTAR'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });
}
