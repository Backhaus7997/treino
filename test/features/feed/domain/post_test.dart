import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/feed/domain/post.dart';
import 'package:treino/features/feed/domain/post_privacy.dart';
import 'package:treino/features/feed/domain/routine_tag.dart';

void main() {
  final createdAt = DateTime.utc(2026, 1, 1, 12, 0, 0);

  group('Post', () {
    // SCENARIO-112: Post default values and field presence
    test('SCENARIO-112: fields non-null, routineTag null when not provided',
        () {
      final post = Post(
        id: 'p1',
        authorUid: 'u1',
        authorGymId: null,
        text: 'First post',
        routineTag: null,
        privacy: PostPrivacy.public,
        createdAt: createdAt,
      );

      expect(post.id, equals('p1'));
      expect(post.authorUid, equals('u1'));
      expect(post.text, equals('First post'));
      expect(post.privacy, equals(PostPrivacy.public));
      expect(post.createdAt, equals(createdAt));
      expect(post.routineTag, isNull);
    });

    // SCENARIO-113: Post toJson/fromJson round-trip with routineTag null
    test('SCENARIO-113: round-trip with routineTag null', () {
      final post = Post(
        id: 'p2',
        authorUid: 'u2',
        authorGymId: 'gym1',
        text: 'No routine',
        routineTag: null,
        privacy: PostPrivacy.friends,
        createdAt: createdAt,
      );

      final json = post.toJson();
      // createdAt is serialized as Timestamp; pass Timestamp for fromJson
      final roundTripped = Post.fromJson(json);
      expect(roundTripped, equals(post));
    });

    // SCENARIO-114: Post toJson/fromJson round-trip with routineTag populated
    test('SCENARIO-114: round-trip with routineTag populated', () {
      final post = Post(
        id: 'p3',
        authorUid: 'u3',
        authorGymId: null,
        text: 'Tagged post',
        routineTag: const RoutineTag(routineId: 'r1', routineName: 'Push Day'),
        privacy: PostPrivacy.gym,
        createdAt: createdAt,
      );

      final json = post.toJson();
      final roundTripped = Post.fromJson(json);
      expect(roundTripped, equals(post));
      expect(roundTripped.routineTag?.routineName, equals('Push Day'));
    });
  });
}
