import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/features/feed/application/suggested_users_providers.dart';
import 'package:treino/features/feed/application/follow_providers.dart'
    show followRepositoryProvider;
import 'package:treino/features/feed/data/follow_repository.dart';
import 'package:treino/features/feed/domain/follow.dart';
import 'package:treino/features/feed/domain/follow_status.dart';
import 'package:treino/features/gyms/domain/gym.dart' show kNoGymId;
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/domain/user_public_profile.dart';
import 'package:treino/features/workout/application/session_providers.dart'
    show currentUidProvider;

class MockFollowRepository extends Mock implements FollowRepository {}

void main() {
  late FakeFirebaseFirestore firestore;

  setUp(() {
    firestore = FakeFirebaseFirestore();
  });

  ProviderContainer buildContainer({
    String? uid = 'me',
    FollowRepository? followRepository,
  }) {
    final container = ProviderContainer(
      overrides: [
        firestoreProvider.overrideWithValue(firestore),
        currentUidProvider.overrideWithValue(uid),
        if (followRepository != null)
          followRepositoryProvider.overrideWithValue(
            followRepository,
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

  /// Siembra UNA arista dirigida. El doc id NO se ordena.
  Future<void> seedEdge({
    required String follower,
    required String followee,
    required FollowStatus status,
  }) {
    final id = Follow.edgeId(follower, followee);
    return firestore.collection('follows').doc(id).set(
          Follow(
            id: id,
            followerUid: follower,
            followeeUid: followee,
            status: status,
            members: [follower, followee],
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

  test('NO excluye a quien me sigue si yo no lo sigo… se excluye igual',
      () async {
    // Nota deliberada: la exclusión es por PRESENCIA de arista, no por
    // dirección. Alguien que ya me mandó solicitud no vuelve a aparecer como
    // sugerencia aunque yo no lo siga — si no, la lista te ofrecería gente que
    // ya está en tu inbox.
    await seedProfile(uid: 'seguidor');
    await seedProfile(uid: 'available');
    await seedEdge(
      follower: 'seguidor',
      followee: 'me',
      status: FollowStatus.accepted,
    );

    final result =
        await buildContainer().read(suggestedUsersProvider('gym-a').future);

    expect(result.map((profile) => profile.uid), ['available']);
  });

  test('excluye a quien ya sigo (arista aceptada)', () async {
    await seedProfile(uid: 'accepted');
    await seedProfile(uid: 'available');
    await seedEdge(
      follower: 'me',
      followee: 'accepted',
      status: FollowStatus.accepted,
    );

    final result =
        await buildContainer().read(suggestedUsersProvider('gym-a').future);

    expect(result.map((profile) => profile.uid), ['available']);
  });

  test('excluye solicitudes pendientes en LAS DOS direcciones', () async {
    // La exclusión sigue siendo por `members array-contains`, o sea que alcanza
    // a las dos direcciones con una sola query. Que el grafo sea dirigido no
    // cambia esto: sugerir a alguien con quien ya hay una arista en cualquier
    // sentido sería ruido.
    await seedProfile(uid: 'outgoing');
    await seedProfile(uid: 'incoming');
    await seedProfile(uid: 'available');
    await seedEdge(
      follower: 'me',
      followee: 'outgoing',
      status: FollowStatus.pending,
    );
    await seedEdge(
      follower: 'incoming',
      followee: 'me',
      status: FollowStatus.pending,
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

  test('returns at most twenty suggestions', () async {
    for (var index = 0; index < 22; index++) {
      final suffix = index.toString().padLeft(2, '0');
      await seedProfile(
        uid: 'candidate-$suffix',
        displayName: 'Candidate $suffix',
      );
    }

    final result =
        await buildContainer().read(suggestedUsersProvider('gym-a').future);

    expect(result, hasLength(kSuggestedUsersLimit));
    expect(
      result.map((profile) => profile.uid),
      [
        for (var index = 0; index < kSuggestedUsersLimit; index++)
          'candidate-${index.toString().padLeft(2, '0')}',
      ],
    );
  });

  test('page N returns the Nth block of eight candidates', () {
    final candidates = [
      for (var index = 0; index < kSuggestedUsersLimit; index++)
        UserPublicProfile(uid: 'candidate-$index', gymId: 'gym-a'),
    ];

    expect(
      suggestedUsersPage(candidates, 1).map((profile) => profile.uid),
      [for (var index = 8; index < 16; index++) 'candidate-$index'],
    );
    expect(
      suggestedUsersPage(candidates, 2).map((profile) => profile.uid),
      [for (var index = 16; index < 20; index++) 'candidate-$index'],
    );
  });

  test('zero candidates produce no suggestion slot', () {
    expect(suggestedUsersAfterPost(const [], 9), isEmpty);
  });

  test('25 posts and 20 candidates produce slots after posts 10 and 20', () {
    final candidates = [
      for (var index = 0; index < kSuggestedUsersLimit; index++)
        UserPublicProfile(uid: 'candidate-$index', gymId: 'gym-a'),
    ];
    final insertionIndexes = [
      for (var postIndex = 0; postIndex < 25; postIndex++)
        if (suggestedUsersAfterPost(candidates, postIndex).isNotEmpty)
          postIndex,
    ];

    expect(insertionIndexes, [9, 19]);
  });

  test('carga las aristas una sola vez, sin lookups por candidato', () async {
    final repository = MockFollowRepository();
    when(() => repository.allOf('me')).thenAnswer((_) async => const []);
    await seedProfile(uid: 'candidate-1');
    await seedProfile(uid: 'candidate-2');

    final result = await buildContainer(followRepository: repository)
        .read(suggestedUsersProvider('gym-a').future);

    expect(result, hasLength(2));
    verify(() => repository.allOf('me')).called(1);
    verifyNever(() => repository.getEdge(any()));
  });
}
