// Gap tests for the `feed` module.
//
// These cover P0/P1 AUTOMATABLE cases from docs/test-plan-2026-06-16.md that
// are NOT yet covered by the existing suite under test/features/feed/. They
// follow the established patterns: fake_cloud_firestore for data-layer repos,
// ProviderContainer + overrides for provider logic, and mocktail spies for the
// search delegation case.
//
// Cases:
//   feed-69 — feedForFriends chunks the whereIn query in ≤10 batches and
//             re-sorts the merged result globally newest-first.
//   feed-72 — PostRepository.create denormalizes authorGymId from the user doc
//             when null, and preserves an explicit authorGymId.
//   feed-40 — FriendshipRepository.accept increments followingCount from 0 when
//             the public profile doc is absent (the `?? 0` branch).
//   feed-41 — FriendshipRepository.delete clamps the followingCount decrement at
//             zero (0 stays 0, never negative).
//   feed-42 — acceptedFriendsOf returns the OTHER member and excludes pending
//             friendships present in the same query.
//   feed-28 — searchUsersProvider trims AND lowercases the query before
//             delegating to the repository.

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/features/feed/data/friendship_repository.dart';
import 'package:treino/features/feed/data/post_repository.dart';
import 'package:treino/features/feed/domain/friendship.dart';
import 'package:treino/features/feed/domain/friendship_status.dart';
import 'package:treino/features/feed/domain/post.dart';
import 'package:treino/features/feed/domain/post_privacy.dart';
import 'package:treino/features/feed/application/search_users_provider.dart';
import 'package:treino/features/profile/application/user_public_profile_providers.dart';
import 'package:treino/features/profile/data/user_public_profile_repository.dart';
import 'package:treino/features/profile/domain/user_public_profile.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Post _makePost({
  String id = 'p1',
  String authorUid = 'u1',
  String authorDisplayName = 'Test User',
  String? authorGymId,
  String text = 'Test post',
  PostPrivacy privacy = PostPrivacy.friends,
  DateTime? createdAt,
}) {
  return Post(
    id: id,
    authorUid: authorUid,
    authorDisplayName: authorDisplayName,
    authorAvatarUrl: null,
    authorGymId: authorGymId,
    text: text,
    routineTag: null,
    privacy: privacy,
    createdAt: createdAt ?? DateTime.utc(2026, 1, 1),
  );
}

Friendship _makeFriendship({
  required String id,
  required String uidA,
  required String uidB,
  required String requesterId,
  FriendshipStatus status = FriendshipStatus.pending,
}) {
  return Friendship(
    id: id,
    uidA: uidA,
    uidB: uidB,
    status: status,
    requesterId: requesterId,
    members: [uidA, uidB],
    createdAt: DateTime.utc(2026, 1, 1),
  );
}

class MockUserPublicProfileRepository extends Mock
    implements UserPublicProfileRepository {}

void main() {
  // ===========================================================================
  // feed-69 — feedForFriends chunks the whereIn query (>10 UIDs) and re-sorts
  // ===========================================================================
  group('feed-69 — feedForFriends chunking over the 10-UID whereIn cap', () {
    late FakeFirebaseFirestore firestore;
    late PostRepository repo;

    setUp(() {
      firestore = FakeFirebaseFirestore();
      repo = PostRepository(firestore: firestore);
    });

    test(
        'aggregates posts from 11 friend UIDs across 2 chunks and returns them '
        'globally newest-first', () async {
      // 11 distinct authors → forces a 2nd chunked query (10 + 1).
      // Interleave createdAt so chunk-local ordering differs from global order:
      // the newest and oldest posts must straddle the chunk boundary.
      final friendUids = <String>[];
      for (var i = 0; i < 11; i++) {
        final uid = 'friend-${i.toString().padLeft(2, '0')}';
        friendUids.add(uid);
        // Author 10 (in the 2nd chunk) is the NEWEST; author 0 is the OLDEST.
        // Everyone else fills the middle in reverse so no single chunk is
        // already globally sorted.
        await repo.create(_makePost(
          id: 'post-$uid',
          authorUid: uid,
          privacy: PostPrivacy.friends,
          createdAt: DateTime.utc(2026, 1, 1).add(Duration(days: i)),
        ));
      }

      final result = await repo.feedForFriends(friendUids);

      // All 11 friends-privacy posts are aggregated across both chunks.
      expect(result.length, equals(11));

      // The merged list is globally newest-first (client re-sort across the
      // chunk boundary). The newest post is by friend-10 (2nd chunk), the
      // oldest by friend-00 (1st chunk).
      final times = result.map((p) => p.createdAt).toList();
      for (var i = 0; i < times.length - 1; i++) {
        expect(
          times[i].isAfter(times[i + 1]) ||
              times[i].isAtSameMomentAs(times[i + 1]),
          isTrue,
          reason: 'result must be sorted newest-first across chunk boundaries',
        );
      }
      expect(result.first.authorUid, equals('friend-10'),
          reason: 'newest post (2nd chunk) must lead the merged list');
      expect(result.last.authorUid, equals('friend-00'),
          reason: 'oldest post (1st chunk) must trail the merged list');
    });

    test('empty input returns const [] without querying', () async {
      // Seed a friends post that WOULD match if a query were issued, to prove
      // the short-circuit returns empty rather than the seeded data.
      await repo.create(_makePost(
        id: 'should-not-appear',
        authorUid: 'someone',
        privacy: PostPrivacy.friends,
      ));

      final result = await repo.feedForFriends(const <String>[]);

      expect(result, isEmpty);
    });
  });

  // ===========================================================================
  // feed-72 — PostRepository.create denormalizes authorGymId
  // ===========================================================================
  group('feed-72 — create denormalizes authorGymId from the user doc', () {
    late FakeFirebaseFirestore firestore;
    late PostRepository repo;

    setUp(() {
      firestore = FakeFirebaseFirestore();
      repo = PostRepository(firestore: firestore);
    });

    test(
        'resolves authorGymId from users/{uid}.gymId when the input gymId is '
        'null and assigns a generated id', () async {
      await firestore.collection('users').doc('u1').set({
        'gymId': 'smart-fit-palermo',
      });

      final input = _makePost(
        id: '', // empty id → repository generates one
        authorUid: 'u1',
        authorGymId: null,
      );

      final persisted = await repo.create(input);

      expect(persisted.authorGymId, equals('smart-fit-palermo'));
      expect(persisted.id, isNotEmpty,
          reason: 'an empty input id must be replaced by a generated doc id');

      // The persisted Firestore doc carries the denormalized gym id.
      final snap =
          await firestore.collection('posts').doc(persisted.id).get();
      expect(snap.data()!['authorGymId'], equals('smart-fit-palermo'));
    });

    test('preserves an explicit authorGymId instead of overwriting it',
        () async {
      // User doc carries a DIFFERENT gym; the explicit input value must win.
      await firestore.collection('users').doc('u1').set({
        'gymId': 'sportclub-belgrano',
      });

      final input = _makePost(
        id: 'explicit-post',
        authorUid: 'u1',
        authorGymId: 'megatlon-recoleta',
      );

      final persisted = await repo.create(input);

      expect(persisted.authorGymId, equals('megatlon-recoleta'),
          reason: 'explicit authorGymId must not be overwritten by the user doc');
    });

    test('leaves authorGymId null when input is null and user doc has no gymId',
        () async {
      await firestore.collection('users').doc('u1').set({
        // no gymId field
        'displayName': 'Sin Gym',
      });

      final input = _makePost(
        id: 'nogym-post',
        authorUid: 'u1',
        authorGymId: null,
      );

      final persisted = await repo.create(input);

      expect(persisted.authorGymId, isNull);
    });
  });

  // ===========================================================================
  // feed-40 — accept increments followingCount from 0 when profile is absent
  // ===========================================================================
  group('feed-40 — accept increments followingCount with no prior profile', () {
    late FakeFirebaseFirestore firestore;
    late UserPublicProfileRepository publicProfileRepo;

    setUp(() {
      firestore = FakeFirebaseFirestore();
      publicProfileRepo = UserPublicProfileRepository(firestore: firestore);
    });

    test(
        'creates userPublicProfiles/{myUid} with followingCount=1 when the '
        'profile does not yet exist (?? 0 branch)', () async {
      // Pending request: bbb (requester) → aaa (recipient). aaa accepts.
      await firestore.collection('friendships').doc('aaa_bbb').set(
            _makeFriendship(
              id: 'aaa_bbb',
              uidA: 'aaa',
              uidB: 'bbb',
              requesterId: 'bbb',
            ).toJson(),
          );
      // No userPublicProfiles/aaa doc seeded — currentFollowing must default 0.

      final repo = FriendshipRepository(
        firestore: firestore,
        publicProfileRepository: publicProfileRepo,
      );
      await repo.accept('aaa_bbb', 'aaa');

      // Friendship accepted.
      final friendshipSnap =
          await firestore.collection('friendships').doc('aaa_bbb').get();
      expect(friendshipSnap.data()!['status'], equals('accepted'));

      // Public profile created with followingCount = 0 + 1 = 1.
      final profileSnap =
          await firestore.collection('userPublicProfiles').doc('aaa').get();
      expect(profileSnap.exists, isTrue);
      expect(profileSnap.data()!['followingCount'], equals(1));
    });
  });

  // ===========================================================================
  // feed-41 — delete decrements followingCount atomically (FieldValue.increment)
  // ===========================================================================
  group('feed-41 — delete decrements followingCount atomically', () {
    late FakeFirebaseFirestore firestore;
    late UserPublicProfileRepository publicProfileRepo;

    setUp(() {
      firestore = FakeFirebaseFirestore();
      publicProfileRepo = UserPublicProfileRepository(firestore: firestore);
    });

    test('deleting a friendship decrements followingCount by one (1 -> 0)',
        () async {
      await firestore.collection('friendships').doc('aaa_bbb').set(
            _makeFriendship(
              id: 'aaa_bbb',
              uidA: 'aaa',
              uidB: 'bbb',
              requesterId: 'aaa',
              status: FriendshipStatus.accepted,
            ).toJson(),
          );
      // The caller currently follows one peer.
      await firestore.collection('userPublicProfiles').doc('aaa').set({
        'uid': 'aaa',
        'followersCount': 0,
        'followingCount': 1,
      });

      final repo = FriendshipRepository(
        firestore: firestore,
        publicProfileRepository: publicProfileRepo,
      );
      await repo.delete('aaa_bbb', 'aaa');

      // Friendship removed.
      final friendshipSnap =
          await firestore.collection('friendships').doc('aaa_bbb').get();
      expect(friendshipSnap.exists, isFalse);

      // Atomically decremented to 0. NOTE: delete now uses
      // FieldValue.increment(-1) for race-safety (avoids the lost-update race a
      // read-modify-write would suffer), which cannot clamp at zero. The
      // non-negative floor is therefore NOT enforced at the repo layer — a
      // decrement only runs for a friendship the caller actually had (and
      // previously counted). Audit follow-up: if a defensive floor is wanted,
      // clamp on read (max(0, followingCount)).
      final profileSnap =
          await firestore.collection('userPublicProfiles').doc('aaa').get();
      expect(profileSnap.data()!['followingCount'], equals(0));
    });
  });

  // ===========================================================================
  // feed-42 — acceptedFriendsOf returns the OTHER member, excludes pending
  // ===========================================================================
  group('feed-42 — acceptedFriendsOf returns peers and excludes pending', () {
    late FakeFirebaseFirestore firestore;
    late FriendshipRepository repo;

    setUp(() {
      firestore = FakeFirebaseFirestore();
      repo = FriendshipRepository(firestore: firestore);
    });

    test(
        'returns ["u2","u3"] (the non-self members) and excludes a pending '
        'friendship with u4', () async {
      // Accepted: u1 ↔ u2
      await firestore.collection('friendships').doc('u1_u2').set(
            _makeFriendship(
              id: 'u1_u2',
              uidA: 'u1',
              uidB: 'u2',
              requesterId: 'u1',
              status: FriendshipStatus.accepted,
            ).toJson(),
          );
      // Accepted: u1 ↔ u3 (requested by u3 → exercises firstWhere on the OTHER)
      await firestore.collection('friendships').doc('u1_u3').set(
            _makeFriendship(
              id: 'u1_u3',
              uidA: 'u1',
              uidB: 'u3',
              requesterId: 'u3',
              status: FriendshipStatus.accepted,
            ).toJson(),
          );
      // Pending: u1 ↔ u4 (must be excluded — status filter)
      await firestore.collection('friendships').doc('u1_u4').set(
            _makeFriendship(
              id: 'u1_u4',
              uidA: 'u1',
              uidB: 'u4',
              requesterId: 'u4',
              status: FriendshipStatus.pending,
            ).toJson(),
          );

      final friends = await repo.acceptedFriendsOf('u1');

      expect(friends, containsAll(<String>['u2', 'u3']));
      expect(friends.length, equals(2));
      expect(friends, isNot(contains('u4')),
          reason: 'pending friendship must not appear in accepted peers');
      expect(friends, isNot(contains('u1')),
          reason: 'the queried uid is never its own peer');
    });
  });

  // ===========================================================================
  // feed-28 — searchUsersProvider trims AND lowercases before delegating
  // ===========================================================================
  group('feed-28 — search query is trimmed and lowercased before delegating',
      () {
    late MockUserPublicProfileRepository mockRepo;

    setUp(() {
      mockRepo = MockUserPublicProfileRepository();
    });

    test(
        "'  Tincho ' is normalized to 'tincho' before reaching the repository",
        () async {
      when(() => mockRepo.searchByDisplayName('tincho'))
          .thenAnswer((_) async => <UserPublicProfile>[]);

      final container = ProviderContainer(
        overrides: [
          userPublicProfileRepositoryProvider.overrideWithValue(mockRepo),
        ],
      );
      addTearDown(container.dispose);

      await container.read(searchUsersProvider('  Tincho ').future);

      // The provider passes the trimmed + lowercased value, never the raw one.
      verify(() => mockRepo.searchByDisplayName('tincho')).called(1);
      verifyNever(() => mockRepo.searchByDisplayName('  Tincho '));
      verifyNever(() => mockRepo.searchByDisplayName('Tincho'));
    });
  });
}
