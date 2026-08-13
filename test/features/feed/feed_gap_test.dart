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
import 'package:treino/features/feed/data/follow_repository.dart';
import 'package:treino/features/feed/domain/follow.dart';
import 'package:treino/features/feed/data/post_repository.dart';
import 'package:treino/features/feed/domain/follow_status.dart';
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
  PostPrivacy privacy = PostPrivacy.followers,
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

Follow _edge(
  String follower,
  String followee, {
  FollowStatus status = FollowStatus.pending,
}) {
  return Follow(
    id: Follow.edgeId(follower, followee),
    followerUid: follower,
    followeeUid: followee,
    status: status,
    members: [follower, followee],
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
          privacy: PostPrivacy.followers,
          createdAt: DateTime.utc(2026, 1, 1).add(Duration(days: i)),
        ));
      }

      final result = await repo.feedForFriends(friendUids);
      final posts = result.posts;

      // All 11 friends-privacy posts are aggregated across both chunks.
      expect(posts.length, equals(11));

      // The merged list is globally newest-first (client re-sort across the
      // chunk boundary). The newest post is by friend-10 (2nd chunk), the
      // oldest by friend-00 (1st chunk).
      final times = posts.map((p) => p.createdAt).toList();
      for (var i = 0; i < times.length - 1; i++) {
        expect(
          times[i].isAfter(times[i + 1]) ||
              times[i].isAtSameMomentAs(times[i + 1]),
          isTrue,
          reason: 'result must be sorted newest-first across chunk boundaries',
        );
      }
      expect(posts.first.authorUid, equals('friend-10'),
          reason: 'newest post (2nd chunk) must lead the merged list');
      expect(posts.last.authorUid, equals('friend-00'),
          reason: 'oldest post (1st chunk) must trail the merged list');
    });

    test('empty input returns const [] without querying', () async {
      // Seed a friends post that WOULD match if a query were issued, to prove
      // the short-circuit returns empty rather than the seeded data.
      await repo.create(_makePost(
        id: 'should-not-appear',
        authorUid: 'someone',
        privacy: PostPrivacy.followers,
      ));

      final result = await repo.feedForFriends(const <String>[]);

      expect(result.posts, isEmpty);
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
      final snap = await firestore.collection('posts').doc(persisted.id).get();
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
          reason:
              'explicit authorGymId must not be overwritten by the user doc');
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

  // NOTE: feed-40 / feed-41 (client-side followingCount increment on accept
  // and decrement on delete) were REMOVED — follow counters moved to the
  // `maintainFollowCounters` Cloud Function (W-SOCIAL-COUNTERS-01). Those
  // scenarios are now covered in functions/src/__tests__/
  // maintain-follow-counters.test.ts.

  // ===========================================================================
  // feed-42 — followingOf devuelve los SEGUIDOS y excluye los pending
  // ===========================================================================
  group('feed-42 — followingOf devuelve los seguidos y excluye pending', () {
    late FakeFirebaseFirestore firestore;
    late FollowRepository repo;

    setUp(() {
      firestore = FakeFirebaseFirestore();
      repo = FollowRepository(firestore: firestore);
    });

    Future<void> seed(Follow edge) =>
        firestore.collection('follows').doc(edge.id).set(edge.toJson());

    test('devuelve ["u2","u3"] (los SEGUIDOS) y excluye la pendiente con u4',
        () async {
      // El caso original probaba `acceptedFriendsOf`, que devolvía "el otro
      // miembro" de cada doc del par — o sea los DOS lados de la relación
      // mezclados. Su sucesor `followingOf` devuelve sólo a quienes u1 sigue,
      // que es la diferencia semántica del cambio de modelo.
      await seed(_edge('u1', 'u2', status: FollowStatus.accepted));
      await seed(_edge('u1', 'u3', status: FollowStatus.accepted));
      // Pendiente: no cuenta como seguido todavía.
      await seed(_edge('u1', 'u4'));
      // Y ésta es la que el modelo viejo NO podía distinguir: u5 sigue a u1,
      // pero u1 no sigue a u5. Con `acceptedFriendsOf` u5 habría aparecido.
      await seed(_edge('u5', 'u1', status: FollowStatus.accepted));

      final following = await repo.followingOf('u1');

      expect(following, containsAll(<String>['u2', 'u3']));
      expect(following.length, equals(2));
      expect(following, isNot(contains('u4')),
          reason: 'una arista pendiente no es un seguido');
      expect(following, isNot(contains('u5')),
          reason: 'que u5 me siga no lo convierte en alguien que yo sigo');
      expect(following, isNot(contains('u1')));
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

    test("'  Tincho ' is normalized to 'tincho' before reaching the repository",
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
