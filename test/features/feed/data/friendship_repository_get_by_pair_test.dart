import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/feed/data/friendship_repository.dart';
import 'package:treino/features/feed/domain/friendship.dart';
import 'package:treino/features/feed/domain/friendship_status.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late FriendshipRepository repo;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    repo = FriendshipRepository(firestore: firestore);
  });

  Future<void> seedFriendship({
    required String uidA,
    required String uidB,
    required String requesterId,
    FriendshipStatus status = FriendshipStatus.pending,
  }) async {
    final id = Friendship.sortedDocId(uidA, uidB);
    final friendship = Friendship(
      id: id,
      uidA: uidA,
      uidB: uidB,
      status: status,
      requesterId: requesterId,
      members: [uidA, uidB],
      createdAt: DateTime.utc(2026, 1, 1),
    );
    await firestore.collection('friendships').doc(id).set(friendship.toJson());
  }

  group('FriendshipRepository.getByPair', () {
    // SCENARIO-190: returns Friendship when doc exists
    test('SCENARIO-190: returns a non-null Friendship when doc exists',
        () async {
      await seedFriendship(
        uidA: 'alice',
        uidB: 'bob',
        requesterId: 'alice',
        status: FriendshipStatus.pending,
      );

      final result = await repo.getByPair('alice', 'bob');

      expect(result, isNotNull);
      expect(result!.requesterId, equals('alice'));
      expect(result.status, equals(FriendshipStatus.pending));
    });

    // SCENARIO-191: returns null when no doc exists
    test('SCENARIO-191: returns null and no exception when no doc exists',
        () async {
      final result = await repo.getByPair('alice', 'bob');

      expect(result, isNull);
    });

    // SCENARIO-192: respects sorted doc ID regardless of argument order
    test('SCENARIO-192: returns same Friendship when arguments are reversed',
        () async {
      await seedFriendship(
        uidA: 'alice',
        uidB: 'bob',
        requesterId: 'alice',
      );

      // Called with reversed order
      final result = await repo.getByPair('bob', 'alice');

      expect(result, isNotNull);
      expect(result!.requesterId, equals('alice'));
    });
  });
}
