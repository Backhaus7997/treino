import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/feed/data/friendship_repository.dart';
import 'package:treino/features/feed/domain/friendship.dart';
import 'package:treino/features/feed/domain/friendship_status.dart';
import 'package:treino/features/profile/data/user_public_profile_repository.dart';

/// Regression test for the non-atomic read-modify-write lost-update bug in
/// [FriendshipRepository.accept] / [FriendshipRepository.delete].
///
/// The old implementation did `get() -> currentFollowing +/- 1 -> set(merge)`.
/// Two concurrent operations both read the same stale `followingCount` and then
/// each wrote `stale + 1`, so one increment was clobbered (final count off by
/// one). With `FieldValue.increment` the two server-side increments compose, so
/// the final count reflects BOTH operations.
void main() {
  late FakeFirebaseFirestore firestore;
  late FriendshipRepository repo;
  late UserPublicProfileRepository publicProfileRepo;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    publicProfileRepo = UserPublicProfileRepository(firestore: firestore);
    repo = FriendshipRepository(
      firestore: firestore,
      publicProfileRepository: publicProfileRepo,
    );
  });

  Future<void> seedPending({
    required String id,
    required String myUid,
    required String otherUid,
  }) async {
    final friendship = Friendship(
      id: id,
      uidA: myUid.compareTo(otherUid) <= 0 ? myUid : otherUid,
      uidB: myUid.compareTo(otherUid) <= 0 ? otherUid : myUid,
      status: FriendshipStatus.pending,
      // requester is the OTHER user so myUid can accept (not self-accept).
      requesterId: otherUid,
      members: [myUid, otherUid],
      createdAt: DateTime.utc(2026, 1, 1),
    );
    await firestore.collection('friendships').doc(id).set(friendship.toJson());
  }

  test(
      'concurrent accepts both count: two interleaved accepts increment '
      'followingCount by 2 (no lost update)', () async {
    await firestore.collection('userPublicProfiles').doc('me').set({
      'uid': 'me',
      'followersCount': 0,
      'followingCount': 0,
    });

    await seedPending(id: 'bob_me', myUid: 'me', otherUid: 'bob');
    await seedPending(id: 'cat_me', myUid: 'me', otherUid: 'cat');

    // Fire both accepts without awaiting in between — under the old
    // read-modify-write both would read followingCount=0 and write 1,
    // dropping one increment. Atomic increments compose to 2.
    await Future.wait([
      repo.accept('bob_me', 'me'),
      repo.accept('cat_me', 'me'),
    ]);

    final snap =
        await firestore.collection('userPublicProfiles').doc('me').get();
    expect(snap.data()!['followingCount'], equals(2));
  });
}
