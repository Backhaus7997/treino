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

  // ---------------------------------------------------------------------------
  // T22: request
  // ---------------------------------------------------------------------------
  group('FriendshipRepository.request', () {
    // SCENARIO-123: request creates doc with sorted id, pending status, correct requesterId
    test(
        'SCENARIO-123: request("bbb","aaa") creates doc at friendships/aaa_bbb',
        () async {
      final friendship = await repo.request('bbb', 'aaa');

      final snap =
          await firestore.collection('friendships').doc('aaa_bbb').get();
      expect(snap.exists, isTrue);

      final data = snap.data()!;
      expect(data['status'], equals('pending'));
      expect(data['requesterId'], equals('bbb'));
      expect(data['members'], containsAll(['bbb', 'aaa']));
      expect(friendship.id, equals('aaa_bbb'));
      expect(friendship.status, equals(FriendshipStatus.pending));
    });
  });

  // ---------------------------------------------------------------------------
  // T24: accept
  // ---------------------------------------------------------------------------
  group('FriendshipRepository.accept', () {
    Future<void> seedFriendship({
      required String id,
      required String requesterId,
      required String uidA,
      required String uidB,
      FriendshipStatus status = FriendshipStatus.pending,
    }) async {
      final now = DateTime.utc(2026, 1, 1);
      final friendship = Friendship(
        id: id,
        uidA: uidA,
        uidB: uidB,
        status: status,
        requesterId: requesterId,
        members: [uidA, uidB],
        createdAt: now,
      );
      await firestore
          .collection('friendships')
          .doc(id)
          .set(friendship.toJson());
    }

    // SCENARIO-124: accept transitions status to accepted when caller is not requester
    test(
        'SCENARIO-124: accept("aaa_bbb","aaa") sets status to accepted when requesterId is bbb',
        () async {
      await seedFriendship(
        id: 'aaa_bbb',
        requesterId: 'bbb',
        uidA: 'aaa',
        uidB: 'bbb',
      );

      await repo.accept('aaa_bbb', 'aaa');

      final snap =
          await firestore.collection('friendships').doc('aaa_bbb').get();
      expect(snap.data()!['status'], equals('accepted'));
    });

    // SCENARIO-125: accept rejects when caller is the requester
    test('SCENARIO-125: accept throws when caller is the requester', () async {
      await seedFriendship(
        id: 'aaa_bbb',
        requesterId: 'aaa',
        uidA: 'aaa',
        uidB: 'bbb',
      );

      expect(
        () => repo.accept('aaa_bbb', 'aaa'),
        throwsA(isA<StateError>()),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // T26: acceptedFriendsOf and pendingRequestsFor
  // ---------------------------------------------------------------------------
  group('FriendshipRepository.acceptedFriendsOf', () {
    // SCENARIO-126: acceptedFriendsOf returns the other UID from each accepted friendship
    test(
        'SCENARIO-126: acceptedFriendsOf("u1") returns ["u2","u3"] from accepted friendships',
        () async {
      final now = DateTime.utc(2026, 1, 1);

      // u1 accepted friendship with u2
      await firestore.collection('friendships').doc('u1_u2').set(
            Friendship(
              id: 'u1_u2',
              uidA: 'u1',
              uidB: 'u2',
              status: FriendshipStatus.accepted,
              requesterId: 'u1',
              members: ['u1', 'u2'],
              createdAt: now,
            ).toJson(),
          );

      // u1 accepted friendship with u3
      await firestore.collection('friendships').doc('u1_u3').set(
            Friendship(
              id: 'u1_u3',
              uidA: 'u1',
              uidB: 'u3',
              status: FriendshipStatus.accepted,
              requesterId: 'u3',
              members: ['u1', 'u3'],
              createdAt: now,
            ).toJson(),
          );

      final friends = await repo.acceptedFriendsOf('u1');

      expect(friends, containsAll(['u2', 'u3']));
      expect(friends.length, equals(2));
    });
  });

  group('FriendshipRepository.pendingRequestsFor', () {
    // SCENARIO-127: pendingRequestsFor returns received (not sent) pending requests
    test(
        'SCENARIO-127: pendingRequestsFor("u1") returns only requests where requesterId != "u1"',
        () async {
      final now = DateTime.utc(2026, 1, 1);

      // u2 sent a request to u1 (u1 is recipient)
      await firestore.collection('friendships').doc('u1_u2').set(
            Friendship(
              id: 'u1_u2',
              uidA: 'u1',
              uidB: 'u2',
              status: FriendshipStatus.pending,
              requesterId: 'u2',
              members: ['u1', 'u2'],
              createdAt: now,
            ).toJson(),
          );

      // u1 sent a request to u3 (u1 is requester — should NOT appear)
      await firestore.collection('friendships').doc('u1_u3').set(
            Friendship(
              id: 'u1_u3',
              uidA: 'u1',
              uidB: 'u3',
              status: FriendshipStatus.pending,
              requesterId: 'u1',
              members: ['u1', 'u3'],
              createdAt: now,
            ).toJson(),
          );

      final pending = await repo.pendingRequestsFor('u1');

      expect(pending.length, equals(1));
      expect(pending.first.requesterId, isNot(equals('u1')));
      expect(pending.first.id, equals('u1_u2'));
    });
  });

  // ---------------------------------------------------------------------------
  // T28: delete and idempotency
  // ---------------------------------------------------------------------------
  group('FriendshipRepository.delete', () {
    // SCENARIO-128: delete removes the friendship doc
    test('SCENARIO-128: delete("aaa_bbb") removes the doc', () async {
      final now = DateTime.utc(2026, 1, 1);
      await firestore.collection('friendships').doc('aaa_bbb').set(
            Friendship(
              id: 'aaa_bbb',
              uidA: 'aaa',
              uidB: 'bbb',
              status: FriendshipStatus.pending,
              requesterId: 'aaa',
              members: ['aaa', 'bbb'],
              createdAt: now,
            ).toJson(),
          );

      await repo.delete('aaa_bbb');

      final snap =
          await firestore.collection('friendships').doc('aaa_bbb').get();
      expect(snap.exists, isFalse);
    });
  });

  group('FriendshipRepository.request idempotency', () {
    // SCENARIO-129: request is idempotent for the same pair
    test(
        'SCENARIO-129: request called twice for same pair creates no duplicate',
        () async {
      await repo.request('aaa', 'bbb');
      final second = await repo.request('aaa', 'bbb');

      // Only one doc exists
      final snap =
          await firestore.collection('friendships').doc('aaa_bbb').get();
      expect(snap.exists, isTrue);

      // Returns existing doc without error
      expect(second.id, equals('aaa_bbb'));
      expect(second.status, equals(FriendshipStatus.pending));
    });
  });
}
