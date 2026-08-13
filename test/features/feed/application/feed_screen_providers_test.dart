import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/features/auth/application/auth_providers.dart';
import 'package:treino/features/feed/application/feed_screen_providers.dart';
import 'package:treino/features/feed/application/follow_providers.dart';
import 'package:treino/features/feed/application/post_providers.dart';
import 'package:treino/features/feed/domain/feed_segment.dart';
import 'package:treino/features/feed/domain/post.dart';
import 'package:treino/features/feed/domain/post_privacy.dart';
import 'package:treino/features/feed/domain/routine_tag.dart';

class MockUser extends Mock implements User {
  final String _uid;
  MockUser({required String uid}) : _uid = uid;
  @override
  String get uid => _uid;
}

Post makePost({
  String id = 'p1',
  String authorUid = 'u1',
  String authorDisplayName = 'Tincho',
  String? authorAvatarUrl,
  String? authorGymId,
  String text = 'Hola mundo',
  RoutineTag? routineTag,
  PostPrivacy privacy = PostPrivacy.followers,
  DateTime? createdAt,
}) =>
    Post(
      id: id,
      authorUid: authorUid,
      authorDisplayName: authorDisplayName,
      authorAvatarUrl: authorAvatarUrl,
      authorGymId: authorGymId,
      text: text,
      routineTag: routineTag,
      privacy: privacy,
      createdAt: createdAt ?? DateTime.utc(2026, 5, 14, 10, 0, 0),
    );

void main() {
  group('FeedSegment', () {
    // SCENARIO-138: feedSegmentProvider initial state is FeedSegment.amigos
    test('SCENARIO-138: default state is FeedSegment.amigos', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(feedSegmentProvider), equals(FeedSegment.amigos));
    });

    // SCENARIO-139: feedSegmentProvider state can be updated
    test('SCENARIO-139: state can be updated via notifier', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(feedSegmentProvider.notifier).state = FeedSegment.gym;
      expect(container.read(feedSegmentProvider), equals(FeedSegment.gym));
    });
  });

  group('myFollowingFeedProvider', () {
    // SCENARIO-140: happy path — auth + seguidos + posts chain
    test('SCENARIO-140: returns posts when user is authenticated with follows',
        () async {
      final user = MockUser(uid: 'u1');
      final posts = [
        makePost(id: 'p1'),
        makePost(id: 'p2'),
        makePost(id: 'p3'),
        makePost(id: 'p4'),
        makePost(id: 'p5'),
      ];

      // Override feedForFriendsProvider for any argument (using overrideWith on
      // the family itself) so list identity doesn't matter.
      final container = ProviderContainer(
        overrides: [
          authStateChangesProvider.overrideWith((ref) => Stream.value(user)),
          followingProvider('u1')
              .overrideWith((ref) => Stream.value(['u2', 'u3'])),
          feedForFriendsProvider.overrideWith((ref, _) => Future.value(posts)),
        ],
      );
      addTearDown(container.dispose);

      final result = await container.read(myFollowingFeedProvider.future);
      expect(result, hasLength(5));
      expect(result, equals(posts));
    });

    // SCENARIO-140b: the current user's own uid is included in the friends
    // query, so their own AMIGOS-privacy posts appear in the feed (QA-FEED-003).
    test('SCENARIO-140b: includes the current user uid in the friends query',
        () async {
      final user = MockUser(uid: 'u1');
      String? capturedKey;

      final container = ProviderContainer(
        overrides: [
          authStateChangesProvider.overrideWith((ref) => Stream.value(user)),
          followingProvider('u1')
              .overrideWith((ref) => Stream.value(['u2', 'u3'])),
          feedForFriendsProvider.overrideWith((ref, key) {
            capturedKey = key;
            return Future.value(const <Post>[]);
          }),
        ],
      );
      addTearDown(container.dispose);

      await container.read(myFollowingFeedProvider.future);
      expect(capturedKey, isNotNull);
      // friendUidsKey sorts+joins with spaces; the own uid must be present.
      expect(capturedKey!.split(' '), containsAll(<String>['u1', 'u2', 'u3']));
    });

    // SCENARIO-141: no friends → STILL returns the user's own friends-privacy
    // posts (QA-FEED-003). Previously returned empty (early-return), which hid
    // the author's own AMIGOS posts.
    test('SCENARIO-141: no friends → still returns own friends-privacy posts',
        () async {
      final user = MockUser(uid: 'u1');
      final ownPosts = [makePost(id: 'own', authorUid: 'u1')];

      final container = ProviderContainer(
        overrides: [
          authStateChangesProvider.overrideWith((ref) => Stream.value(user)),
          followingProvider('u1')
              .overrideWith((ref) => Stream.value(const <String>[])),
          feedForFriendsProvider
              .overrideWith((ref, _) => Future.value(ownPosts)),
        ],
      );
      addTearDown(container.dispose);

      final result = await container.read(myFollowingFeedProvider.future);
      expect(result, equals(ownPosts));
    });

    // SCENARIO-814 — EL FEED ES DIRIGIDO.
    //
    // La query se arma con a quiénes SIGO, no con "con quiénes tengo relación".
    // Con `acceptedFriendsProvider` los dos lados de la relación entraban en el
    // mismo conjunto, así que alguien que me sigue sin que yo lo siga aparecía
    // en mi feed. Acá `u3` sigue a `u1`, pero `u1` sólo sigue a `u2`: la key
    // NO puede contener a u3.
    test('SCENARIO-814: la key son los que SIGO, no los que me siguen',
        () async {
      final user = MockUser(uid: 'u1');
      String? capturedKey;

      final container = ProviderContainer(
        overrides: [
          authStateChangesProvider.overrideWith((ref) => Stream.value(user)),
          // u1 sigue solamente a u2.
          followingProvider('u1')
              .overrideWith((ref) => Stream.value(const ['u2'])),
          // u3 sigue a u1 — no tiene que aportar nada al feed de u1.
          followingProvider('u3')
              .overrideWith((ref) => Stream.value(const ['u1'])),
          feedForFriendsProvider.overrideWith((ref, key) {
            capturedKey = key;
            return Future.value(const <Post>[]);
          }),
        ],
      );
      addTearDown(container.dispose);

      await container.read(myFollowingFeedProvider.future);
      final uids = capturedKey!.split(' ');
      expect(uids, containsAll(<String>['u1', 'u2']));
      expect(uids, isNot(contains('u3')),
          reason: 'que u3 me siga no mete sus posts en mi feed');
    });

    // SCENARIO-142: unauthenticated (auth == null) → empty list
    test('SCENARIO-142: returns empty list when user is unauthenticated',
        () async {
      final container = ProviderContainer(
        overrides: [
          authStateChangesProvider
              .overrideWith((ref) => Stream<User?>.value(null)),
        ],
      );
      addTearDown(container.dispose);

      final result = await container.read(myFollowingFeedProvider.future);
      expect(result, isEmpty);
    });

    // SCENARIO-143: myFollowingFeedProvider is a plain FutureProvider (not a family)
    test(
        'SCENARIO-143: myFollowingFeedProvider is FutureProvider<List<Post>> — not a family',
        () {
      expect(myFollowingFeedProvider, isA<FutureProvider<List<Post>>>());
    });
  });
}
