import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/feed/application/post_providers.dart';
import 'package:treino/features/feed/data/post_repository.dart';
import 'package:treino/features/feed/domain/post.dart';
import 'package:treino/features/feed/domain/post_privacy.dart';

Post _makePost({
  required String id,
  required int day,
  String authorUid = 'u1',
  String? authorGymId,
  PostPrivacy privacy = PostPrivacy.public,
}) =>
    Post(
      id: id,
      authorUid: authorUid,
      authorDisplayName: 'Test User',
      authorAvatarUrl: null,
      authorGymId: authorGymId,
      text: 'Post $id',
      routineTag: null,
      privacy: privacy,
      createdAt: DateTime.utc(2026, 1, day),
    );

void main() {
  late FakeFirebaseFirestore firestore;
  late PostRepository repository;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    repository = PostRepository(firestore: firestore);
  });

  Future<void> seedPosts({
    required PostPrivacy privacy,
    String? authorGymId,
  }) async {
    for (var day = 1; day <= 25; day++) {
      await repository.create(_makePost(
        id: '${privacy.name}-$day',
        day: day,
        authorGymId: authorGymId,
        privacy: privacy,
      ));
    }
  }

  ProviderContainer makeContainer() {
    final container = ProviderContainer(
      overrides: [postRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('feedPublicProvider initially exposes the first 20 posts', () async {
    await seedPosts(privacy: PostPrivacy.public);
    final container = makeContainer();

    final result = await container.read(feedPublicProvider.future);

    expect(result, hasLength(20));
    expect(result.first.id, 'public-25');
    expect(result.last.id, 'public-6');
  });

  test('feedForFriendsProvider initially exposes the first 20 posts', () async {
    await seedPosts(privacy: PostPrivacy.friends);
    final container = makeContainer();

    final result = await container.read(feedForFriendsProvider('u1').future);

    expect(result, hasLength(20));
    expect(result.first.id, 'friends-25');
    expect(result.last.id, 'friends-6');
  });

  test('feedForGymProvider initially exposes the first 20 posts', () async {
    await seedPosts(privacy: PostPrivacy.gym, authorGymId: 'gym-1');
    final container = makeContainer();

    final result = await container.read(feedForGymProvider('gym-1').future);

    expect(result, hasLength(20));
    expect(result.first.id, 'gym-25');
    expect(result.last.id, 'gym-6');
  });
}
