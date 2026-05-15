import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
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
        authorDisplayName: 'Test',
        authorAvatarUrl: null,
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
        authorDisplayName: 'Test',
        authorAvatarUrl: null,
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
        authorDisplayName: 'Test',
        authorAvatarUrl: null,
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

    // -------------------------------------------------------------------------
    // SCENARIO-133..137 — author field roundtrip + resilience
    // -------------------------------------------------------------------------

    // SCENARIO-133: Roundtrip serialization preserves all 9 fields
    test(
        'SCENARIO-133: roundtrip preserves all 9 fields including author fields',
        () {
      final post = Post(
        id: 'p4',
        authorUid: 'u4',
        authorDisplayName: 'Tincho',
        authorAvatarUrl: 'https://example.com/av.jpg',
        authorGymId: 'gym-alpha',
        text: 'Full roundtrip test',
        routineTag: const RoutineTag(routineId: 'r1', routineName: 'Push Day'),
        privacy: PostPrivacy.friends,
        createdAt: createdAt,
      );

      final roundTripped = Post.fromJson(post.toJson());
      expect(roundTripped, equals(post));
    });

    // SCENARIO-134: fromJson resilience: missing authorDisplayName defaults to 'Anónimo'
    test(
        'SCENARIO-134: fromJson with missing authorDisplayName defaults to Anónimo',
        () {
      final json = <String, Object?>{
        'id': 'p5',
        'authorUid': 'u5',
        'authorGymId': null,
        'text': 'Old doc',
        'routineTag': null,
        'privacy': 'public',
        'createdAt': Timestamp.fromDate(DateTime.utc(2026, 1, 1, 12, 0, 0)),
        // 'authorDisplayName' intentionally missing
        // 'authorAvatarUrl' intentionally missing
      };

      late Post result;
      expect(() => result = Post.fromJson(json), returnsNormally);
      expect(result.authorDisplayName, equals('Anónimo'));
    });

    // SCENARIO-135: fromJson resilience: null authorAvatarUrl in map → null on model
    test('SCENARIO-135: fromJson with null authorAvatarUrl yields null', () {
      final json = <String, Object?>{
        'id': 'p6',
        'authorUid': 'u6',
        'authorDisplayName': 'Sofía',
        'authorAvatarUrl': null,
        'authorGymId': null,
        'text': 'Null avatar',
        'routineTag': null,
        'privacy': 'public',
        'createdAt': Timestamp.fromDate(DateTime.utc(2026, 1, 1, 12, 0, 0)),
      };

      final result = Post.fromJson(json);
      expect(result.authorAvatarUrl, isNull);
    });

    // SCENARIO-136: fromJson resilience: missing authorAvatarUrl key → null on model
    test('SCENARIO-136: fromJson with missing authorAvatarUrl key yields null',
        () {
      final json = <String, Object?>{
        'id': 'p7',
        'authorUid': 'u7',
        'authorDisplayName': 'Mateo',
        // 'authorAvatarUrl' intentionally absent
        'authorGymId': null,
        'text': 'Missing avatar key',
        'routineTag': null,
        'privacy': 'public',
        'createdAt': Timestamp.fromDate(DateTime.utc(2026, 1, 1, 12, 0, 0)),
      };

      final result = Post.fromJson(json);
      expect(result.authorAvatarUrl, isNull);
    });

    // SCENARIO-137: All existing Post fixture calls updated (compile-time gate)
    // Verified by: flutter analyze exits 0 with no missing-required-param errors.
    // The test below is a compile-time smoke pump — if this file compiles, gate passes.
    test(
        'SCENARIO-137: Post constructor requires authorDisplayName at compile time',
        () {
      // This test asserts the constructor works with the required field present.
      // The RED state before TASK-002b is a compile error — this file intentionally
      // fails to compile until authorDisplayName is added to Post.
      final post = Post(
        id: 'gate',
        authorUid: 'u0',
        authorDisplayName: 'RequiredField',
        authorAvatarUrl: null,
        authorGymId: null,
        text: 'compile gate',
        routineTag: null,
        privacy: PostPrivacy.public,
        createdAt: createdAt,
      );
      expect(post.authorDisplayName, equals('RequiredField'));
    });
  });
}
