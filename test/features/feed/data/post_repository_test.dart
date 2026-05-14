import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/feed/data/post_repository.dart';
import 'package:treino/features/feed/domain/post.dart';
import 'package:treino/features/feed/domain/post_privacy.dart';
import 'package:treino/features/feed/domain/routine_tag.dart';

Post _makePost({
  String id = 'p1',
  String authorUid = 'u1',
  String? authorGymId,
  String text = 'Test post',
  RoutineTag? routineTag,
  PostPrivacy privacy = PostPrivacy.public,
  DateTime? createdAt,
}) {
  return Post(
    id: id,
    authorUid: authorUid,
    authorGymId: authorGymId,
    text: text,
    routineTag: routineTag,
    privacy: privacy,
    createdAt: createdAt ?? DateTime.utc(2026, 1, 1),
  );
}

void main() {
  late FakeFirebaseFirestore firestore;
  late PostRepository repo;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    repo = PostRepository(firestore: firestore);
  });

  // ---------------------------------------------------------------------------
  // T16: create and byAuthor
  // ---------------------------------------------------------------------------
  group('PostRepository.create', () {
    // SCENARIO-118: create writes doc at posts/{post.id} with matching fields
    test('SCENARIO-118: create writes doc at posts/p1 with matching fields',
        () async {
      final post = _makePost(id: 'p1', authorUid: 'u1', text: 'Hello');

      await repo.create(post);

      final snap = await firestore.collection('posts').doc('p1').get();
      expect(snap.exists, isTrue);
      final data = snap.data()!;
      expect(data['authorUid'], equals('u1'));
      expect(data['text'], equals('Hello'));
      expect(data['privacy'], equals('public'));
    });
  });

  group('PostRepository.byAuthor', () {
    // SCENARIO-119: byAuthor returns only posts for the given UID
    test('SCENARIO-119: byAuthor returns only authorUid=u1 posts', () async {
      await repo.create(_makePost(id: 'p1', authorUid: 'u1'));
      await repo.create(_makePost(id: 'p2', authorUid: 'u2'));

      final result = await repo.byAuthor('u1');

      expect(result.length, equals(1));
      expect(result.first.authorUid, equals('u1'));
    });
  });

  // ---------------------------------------------------------------------------
  // T18: feedPublic and feedForFriends
  // ---------------------------------------------------------------------------
  group('PostRepository.feedPublic', () {
    // SCENARIO-120: feedPublic returns only public posts
    test('SCENARIO-120: feedPublic returns only privacy=public posts',
        () async {
      await repo.create(
          _makePost(id: 'pub1', authorUid: 'u1', privacy: PostPrivacy.public));
      await repo.create(
          _makePost(id: 'fri1', authorUid: 'u2', privacy: PostPrivacy.friends));
      await repo.create(
          _makePost(id: 'gym1', authorUid: 'u3', privacy: PostPrivacy.gym));

      final result = await repo.feedPublic();

      expect(result.length, equals(1));
      expect(result.first.privacy, equals(PostPrivacy.public));
    });
  });

  group('PostRepository.feedForFriends', () {
    // SCENARIO-121: feedForFriends returns friends-privacy posts by known friends
    test(
        'SCENARIO-121: feedForFriends returns friends-privacy posts by uidB and uidC only',
        () async {
      await repo.create(
          _makePost(id: 'f1', authorUid: 'uidB', privacy: PostPrivacy.friends));
      await repo.create(
          _makePost(id: 'f2', authorUid: 'uidC', privacy: PostPrivacy.friends));
      // uidD has public post — should not appear in friends feed
      await repo.create(
          _makePost(id: 'f3', authorUid: 'uidD', privacy: PostPrivacy.public));

      final result = await repo.feedForFriends(['uidB', 'uidC']);

      expect(result.length, equals(2));
      final authorUids = result.map((p) => p.authorUid).toList();
      expect(authorUids, containsAll(['uidB', 'uidC']));
    });

    // TODO: edge case — feedForFriends with >10 UIDs requires chunking
    // (Firestore `in` operator limit is 10). No SCENARIO defined for this,
    // but the implementation chunks client-side. Consider adding a stress test.
    test('feedForFriends: empty list returns empty result', () async {
      await repo.create(
          _makePost(id: 'f1', authorUid: 'uidB', privacy: PostPrivacy.friends));

      final result = await repo.feedForFriends([]);

      expect(result, isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  // T20: feedForGym
  // ---------------------------------------------------------------------------
  group('PostRepository.feedForGym', () {
    // SCENARIO-122: feedForGym returns gym-privacy posts by same-gym authors
    test(
        'SCENARIO-122: feedForGym("gym1") returns post with privacy=gym and authorGymId=gym1',
        () async {
      await repo.create(_makePost(
        id: 'g1',
        authorUid: 'u1',
        authorGymId: 'gym1',
        privacy: PostPrivacy.gym,
      ));
      // Post with different gym should not appear
      await repo.create(_makePost(
        id: 'g2',
        authorUid: 'u2',
        authorGymId: 'gym2',
        privacy: PostPrivacy.gym,
      ));
      // Post with null authorGymId (user has no gym) should not appear
      // NOTE: feedForGym does not include posts with authorGymId == null
      await repo.create(_makePost(
        id: 'g3',
        authorUid: 'u3',
        authorGymId: null,
        privacy: PostPrivacy.gym,
      ));

      final result = await repo.feedForGym('gym1');

      expect(result.length, equals(1));
      expect(result.first.authorGymId, equals('gym1'));
      expect(result.first.privacy, equals(PostPrivacy.gym));
    });
  });
}
