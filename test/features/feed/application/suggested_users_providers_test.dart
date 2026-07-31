import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/features/feed/application/suggested_users_providers.dart';
import 'package:treino/features/feed/application/friendship_providers.dart'
    show friendshipRepositoryProvider;
import 'package:treino/features/feed/data/friendship_repository.dart';
import 'package:treino/features/feed/domain/friendship.dart';
import 'package:treino/features/feed/domain/friendship_status.dart';
import 'package:treino/features/gyms/domain/gym.dart' show kNoGymId;
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/domain/user_public_profile.dart';
import 'package:treino/features/workout/application/session_providers.dart'
    show currentUidProvider;

class MockFriendshipRepository extends Mock implements FriendshipRepository {}

void main() {
  late FakeFirebaseFirestore firestore;

  setUp(() {
    firestore = FakeFirebaseFirestore();
  });

  ProviderContainer buildContainer({
    String? uid = 'me',
    FriendshipRepository? friendshipRepository,
  }) {
    final container = ProviderContainer(
      overrides: [
        firestoreProvider.overrideWithValue(firestore),
        currentUidProvider.overrideWithValue(uid),
        if (friendshipRepository != null)
          friendshipRepositoryProvider.overrideWithValue(
            friendshipRepository,
          ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  Future<void> seedProfile({
    required String uid,
    String gymId = 'gym-a',
    String? displayName,
  }) {
    final name = displayName ?? uid;
    return firestore.collection('userPublicProfiles').doc(uid).set(
          UserPublicProfile(
            uid: uid,
            displayName: name,
            displayNameLowercase: name.toLowerCase(),
            gymId: gymId,
          ).toJson(),
        );
  }

  Future<void> seedRelationship({
    required String firstUid,
    required String secondUid,
    required String requesterId,
    required FriendshipStatus status,
  }) {
    final members = [firstUid, secondUid]..sort();
    final id = Friendship.sortedDocId(firstUid, secondUid);
    return firestore.collection('friendships').doc(id).set(
          Friendship(
            id: id,
            uidA: members.first,
            uidB: members.last,
            status: status,
            requesterId: requesterId,
            members: members,
            createdAt: DateTime.utc(2026, 7, 30),
          ).toJson(),
        );
  }

  test('excludes the current user from same-gym suggestions', () async {
    await seedProfile(uid: 'me');
    await seedProfile(uid: 'candidate');

    final result =
        await buildContainer().read(suggestedUsersProvider('gym-a').future);

    expect(result.map((profile) => profile.uid), ['candidate']);
  });

  test('excludes accepted friendships', () async {
    await seedProfile(uid: 'accepted');
    await seedProfile(uid: 'available');
    await seedRelationship(
      firstUid: 'me',
      secondUid: 'accepted',
      requesterId: 'me',
      status: FriendshipStatus.accepted,
    );

    final result =
        await buildContainer().read(suggestedUsersProvider('gym-a').future);

    expect(result.map((profile) => profile.uid), ['available']);
  });

  test('excludes pending requests in both directions', () async {
    await seedProfile(uid: 'outgoing');
    await seedProfile(uid: 'incoming');
    await seedProfile(uid: 'available');
    await seedRelationship(
      firstUid: 'me',
      secondUid: 'outgoing',
      requesterId: 'me',
      status: FriendshipStatus.pending,
    );
    await seedRelationship(
      firstUid: 'me',
      secondUid: 'incoming',
      requesterId: 'incoming',
      status: FriendshipStatus.pending,
    );

    final result =
        await buildContainer().read(suggestedUsersProvider('gym-a').future);

    expect(result.map((profile) => profile.uid), ['available']);
  });

  test('returns no suggestions when the user has no gym', () async {
    await seedProfile(uid: 'candidate');
    final container = buildContainer();

    expect(
      await container.read(suggestedUsersProvider(kNoGymId).future),
      isEmpty,
    );
    expect(
      await container.read(suggestedUsersProvider('').future),
      isEmpty,
    );
  });

  test('returns at most five suggestions', () async {
    for (var index = 0; index < 7; index++) {
      await seedProfile(
        uid: 'candidate-$index',
        displayName: 'Candidate $index',
      );
    }

    final result =
        await buildContainer().read(suggestedUsersProvider('gym-a').future);

    expect(result, hasLength(kSuggestedUsersLimit));
    expect(
      result.map((profile) => profile.uid),
      [
        'candidate-0',
        'candidate-1',
        'candidate-2',
        'candidate-3',
        'candidate-4',
      ],
    );
  });

  test('loads friendships once and never performs per-candidate pair lookups',
      () async {
    final repository = MockFriendshipRepository();
    when(() => repository.allOf('me')).thenAnswer((_) async => const []);
    await seedProfile(uid: 'candidate-1');
    await seedProfile(uid: 'candidate-2');

    final result = await buildContainer(friendshipRepository: repository)
        .read(suggestedUsersProvider('gym-a').future);

    expect(result, hasLength(2));
    verify(() => repository.allOf('me')).called(1);
    verifyNever(() => repository.getByPair(any(), any()));
  });
}
