// Unit tests for `visiblePostsByAuthorProvider`.
//
// Enforces the Option X privacy model on the "ACTIVIDAD" tab of another
// user's public profile:
//   - public → visible to everyone
//   - friends → visible if the viewer is an accepted follower
//   - gym → visible if the viewer shares the target's gym
// The viewer sees their OWN posts unconditionally (isSelf fast path).

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' show User;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/features/auth/application/auth_providers.dart';
import 'package:treino/features/feed/application/post_providers.dart';
import 'package:treino/features/feed/application/public_profile_providers.dart';
import 'package:treino/features/feed/domain/friendship.dart';
import 'package:treino/features/feed/domain/friendship_status.dart';
import 'package:treino/features/profile/application/user_public_profile_providers.dart';
import 'package:treino/features/profile/data/user_public_profile_repository.dart';
import 'package:treino/features/profile/domain/user_public_profile.dart';
import 'package:treino/features/profile/application/user_providers.dart'
    show firestoreProvider;

class _MockUser extends Mock implements User {}

User _userWithUid(String uid) {
  final u = _MockUser();
  when(() => u.uid).thenReturn(uid);
  return u;
}

Future<void> _seedPost(
  FakeFirebaseFirestore firestore, {
  required String id,
  required String authorUid,
  required String privacy,
  String? authorGymId,
  DateTime? createdAt,
}) async {
  await firestore.collection('posts').doc(id).set({
    'id': id,
    'authorUid': authorUid,
    'authorDisplayName': 'Author $authorUid',
    'authorAvatarUrl': null,
    'authorGymId': authorGymId,
    'text': 'Post $id',
    'routineTag': null,
    'privacy': privacy,
    'createdAt': createdAt ?? DateTime.utc(2026, 1, 1),
  });
}

ProviderContainer _makeContainer({
  required FakeFirebaseFirestore firestore,
  required String viewerUid,
  Friendship? friendshipWithTarget,
  UserPublicProfile? viewerProfile,
}) {
  final container = ProviderContainer(
    overrides: [
      firestoreProvider.overrideWithValue(firestore),
      authStateChangesProvider.overrideWith(
        (_) => Stream.value(_userWithUid(viewerUid)),
      ),
      friendshipByPairProvider.overrideWith((ref, pair) async* {
        yield friendshipWithTarget;
      }),
      // Override the viewer's public profile so we can control their gymId.
      // Other uids fall through to the fake Firestore (empty by default).
      userPublicProfileProvider.overrideWith((ref, uid) async* {
        if (uid == viewerUid) {
          yield viewerProfile ??
              UserPublicProfile(uid: viewerUid, gymId: null);
        } else {
          yield* ref
              .watch(userPublicProfileRepositoryProvider)
              .watch(uid);
        }
      }),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  const viewer = 'viewer-uid';
  const target = 'target-uid';

  group('visiblePostsByAuthorProvider', () {
    test('public posts are always visible', () async {
      final firestore = FakeFirebaseFirestore();
      await _seedPost(firestore,
          id: 'p-pub', authorUid: target, privacy: 'public');

      final container = _makeContainer(
        firestore: firestore,
        viewerUid: viewer,
      );

      final posts =
          await container.read(visiblePostsByAuthorProvider(target).future);
      expect(posts.map((p) => p.id), ['p-pub']);
    });

    test('friends posts are hidden when viewer is not accepted', () async {
      final firestore = FakeFirebaseFirestore();
      await _seedPost(firestore,
          id: 'p-friends', authorUid: target, privacy: 'friends');

      final container = _makeContainer(
        firestore: firestore,
        viewerUid: viewer,
        friendshipWithTarget: null,
      );

      final posts =
          await container.read(visiblePostsByAuthorProvider(target).future);
      expect(posts, isEmpty);
    });

    test('friends posts are hidden when friendship is pending', () async {
      final firestore = FakeFirebaseFirestore();
      await _seedPost(firestore,
          id: 'p-friends', authorUid: target, privacy: 'friends');

      final container = _makeContainer(
        firestore: firestore,
        viewerUid: viewer,
        friendshipWithTarget: Friendship(
          id: '${target}_$viewer',
          uidA: target,
          uidB: viewer,
          status: FriendshipStatus.pending,
          requesterId: viewer,
          members: const [target, viewer],
          createdAt: DateTime.utc(2026, 1, 1),
        ),
      );

      final posts =
          await container.read(visiblePostsByAuthorProvider(target).future);
      expect(posts, isEmpty);
    });

    test('friends posts are visible when viewer is an accepted follower',
        () async {
      final firestore = FakeFirebaseFirestore();
      await _seedPost(firestore,
          id: 'p-friends', authorUid: target, privacy: 'friends');

      final container = _makeContainer(
        firestore: firestore,
        viewerUid: viewer,
        friendshipWithTarget: Friendship(
          id: '${target}_$viewer',
          uidA: target,
          uidB: viewer,
          status: FriendshipStatus.accepted,
          requesterId: viewer,
          members: const [target, viewer],
          createdAt: DateTime.utc(2026, 1, 1),
        ),
      );

      final posts =
          await container.read(visiblePostsByAuthorProvider(target).future);
      expect(posts.map((p) => p.id), ['p-friends']);
    });

    test('gym posts are visible only when viewer shares the target gym',
        () async {
      final firestore = FakeFirebaseFirestore();
      await _seedPost(firestore,
          id: 'p-gym',
          authorUid: target,
          privacy: 'gym',
          authorGymId: 'gym-A');
      await _seedPost(firestore,
          id: 'p-gym-other',
          authorUid: target,
          privacy: 'gym',
          authorGymId: 'gym-B');

      final container = _makeContainer(
        firestore: firestore,
        viewerUid: viewer,
        viewerProfile: UserPublicProfile(uid: viewer, gymId: 'gym-A'),
      );

      final posts =
          await container.read(visiblePostsByAuthorProvider(target).future);
      expect(posts.map((p) => p.id), ['p-gym']);
    });

    test('gym posts are hidden when viewer has no gym', () async {
      final firestore = FakeFirebaseFirestore();
      await _seedPost(firestore,
          id: 'p-gym',
          authorUid: target,
          privacy: 'gym',
          authorGymId: 'gym-A');

      final container = _makeContainer(
        firestore: firestore,
        viewerUid: viewer,
        viewerProfile: UserPublicProfile(uid: viewer, gymId: null),
      );

      final posts =
          await container.read(visiblePostsByAuthorProvider(target).future);
      expect(posts, isEmpty);
    });

    test('isSelf → viewer sees ALL their own posts regardless of privacy',
        () async {
      final firestore = FakeFirebaseFirestore();
      await _seedPost(firestore,
          id: 'p-pub', authorUid: viewer, privacy: 'public');
      await _seedPost(firestore,
          id: 'p-friends', authorUid: viewer, privacy: 'friends');
      await _seedPost(firestore,
          id: 'p-gym',
          authorUid: viewer,
          privacy: 'gym',
          authorGymId: 'gym-X');

      final container = _makeContainer(
        firestore: firestore,
        viewerUid: viewer,
      );

      final posts =
          await container.read(visiblePostsByAuthorProvider(viewer).future);
      expect(posts.map((p) => p.id).toSet(),
          {'p-pub', 'p-friends', 'p-gym'});
    });

    test('result is sorted newest-first', () async {
      final firestore = FakeFirebaseFirestore();
      await _seedPost(firestore,
          id: 'p-old',
          authorUid: target,
          privacy: 'public',
          createdAt: DateTime.utc(2026, 1, 1));
      await _seedPost(firestore,
          id: 'p-new',
          authorUid: target,
          privacy: 'public',
          createdAt: DateTime.utc(2026, 6, 1));
      await _seedPost(firestore,
          id: 'p-mid',
          authorUid: target,
          privacy: 'public',
          createdAt: DateTime.utc(2026, 3, 1));

      final container = _makeContainer(
        firestore: firestore,
        viewerUid: viewer,
      );

      final posts =
          await container.read(visiblePostsByAuthorProvider(target).future);
      expect(posts.map((p) => p.id), ['p-new', 'p-mid', 'p-old']);
    });
  });
}
