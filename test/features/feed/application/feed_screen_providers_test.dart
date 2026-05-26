import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/features/auth/application/auth_providers.dart';
import 'package:treino/features/feed/application/feed_screen_providers.dart';
import 'package:treino/features/feed/application/friendship_providers.dart';
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
  PostPrivacy privacy = PostPrivacy.friends,
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

  group('myFriendsFeedProvider', () {
    // SCENARIO-140: happy path — auth + friends + posts chain
    test('SCENARIO-140: returns posts when user is authenticated with friends',
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
          acceptedFriendsProvider('u1')
              .overrideWith((ref) => Stream.value(['u2', 'u3'])),
          feedForFriendsProvider.overrideWith((ref, _) => Future.value(posts)),
        ],
      );
      addTearDown(container.dispose);

      final result = await container.read(myFriendsFeedProvider.future);
      expect(result, hasLength(5));
      expect(result, equals(posts));
    });

    // SCENARIO-141: no friends → empty list, no crash
    test('SCENARIO-141: returns empty list when user has no friends', () async {
      final user = MockUser(uid: 'u1');

      final container = ProviderContainer(
        overrides: [
          authStateChangesProvider.overrideWith((ref) => Stream.value(user)),
          acceptedFriendsProvider('u1')
              .overrideWith((ref) => Stream.value(const <String>[])),
        ],
      );
      addTearDown(container.dispose);

      final result = await container.read(myFriendsFeedProvider.future);
      expect(result, isEmpty);
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

      final result = await container.read(myFriendsFeedProvider.future);
      expect(result, isEmpty);
    });

    // SCENARIO-143: myFriendsFeedProvider is a plain FutureProvider (not a family)
    test(
        'SCENARIO-143: myFriendsFeedProvider is FutureProvider<List<Post>> — not a family',
        () {
      expect(myFriendsFeedProvider, isA<FutureProvider<List<Post>>>());
    });
  });
}
