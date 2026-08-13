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
import 'package:treino/core/utils/geohash.dart';
import 'package:treino/features/gyms/domain/gym.dart' show Gym, kNoGymId;
import 'package:treino/features/gyms/domain/gym_source.dart';
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

  group('cercanía — cuando el propio gym no alcanza', () {
    // Palermo, CABA. Los geohashes se calculan con la función real en vez de
    // hardcodearse: si algún día cambia la precisión del geohash, el test
    // sigue midiendo cercanía y no una constante que quedó vieja.
    const myLat = -34.5875;
    const myLng = -58.4300;

    Future<void> seedGym({
      required String id,
      required double lat,
      required double lng,
    }) =>
        firestore.collection('gyms').doc(id).set(
              Gym(
                id: id,
                name: id,
                lat: lat,
                lng: lng,
                geohash: geohash5(lat, lng),
                source: GymSource.seed,
                createdAt: DateTime.utc(2026, 7, 30),
              ).toJson(),
            );

    late MockFollowRepository repository;

    setUp(() {
      repository = MockFollowRepository();
      when(() => repository.allOf('me')).thenAnswer((_) async => const []);
    });

    test('completa con gente de un gym cercano', () async {
      await seedGym(id: 'gym-a', lat: myLat, lng: myLng);
      // ~1,2km: cae en la misma celda o en una vecina inmediata.
      await seedGym(id: 'gym-cerca', lat: myLat - 0.011, lng: myLng);
      await seedProfile(uid: 'vecino', gymId: 'gym-cerca');

      final result = await buildContainer(followRepository: repository)
          .read(suggestedUsersProvider('gym-a').future);

      expect(result.map((p) => p.uid), ['vecino']);
    });

    test('un gym lejano queda afuera de la grilla', () async {
      await seedGym(id: 'gym-a', lat: myLat, lng: myLng);
      // Córdoba, a ~650km. Ni el 5×5 llega hasta ahí.
      await seedGym(id: 'gym-lejos', lat: -31.4201, lng: -64.1888);
      await seedProfile(uid: 'cordobes', gymId: 'gym-lejos');

      final result = await buildContainer(followRepository: repository)
          .read(suggestedUsersProvider('gym-a').future);

      expect(result, isEmpty);
    });

    test('el propio gym va primero y los cercanos se ordenan por distancia',
        () async {
      await seedGym(id: 'gym-a', lat: myLat, lng: myLng);
      await seedGym(id: 'gym-cerca', lat: myLat - 0.009, lng: myLng);
      await seedGym(id: 'gym-medio', lat: myLat - 0.030, lng: myLng);

      await seedProfile(uid: 'z-del-propio', gymId: 'gym-a');
      await seedProfile(uid: 'a-del-medio', gymId: 'gym-medio');
      await seedProfile(uid: 'm-del-cerca', gymId: 'gym-cerca');

      final result = await buildContainer(followRepository: repository)
          .read(suggestedUsersProvider('gym-a').future);

      // El del propio gym encabeza aunque alfabéticamente vaya último, y
      // entre los de afuera manda la distancia, no el nombre.
      expect(
        result.map((p) => p.uid),
        ['z-del-propio', 'm-del-cerca', 'a-del-medio'],
      );
    });

    test('las aristas también excluyen a los de gyms cercanos', () async {
      when(() => repository.allOf('me')).thenAnswer(
        (_) async => [
          Follow(
            id: Follow.edgeId('vecino', 'me'),
            followerUid: 'vecino',
            followeeUid: 'me',
            status: FollowStatus.pending,
            members: const ['vecino', 'me'],
            createdAt: DateTime.utc(2026, 7, 30),
          ),
        ],
      );
      await seedGym(id: 'gym-a', lat: myLat, lng: myLng);
      await seedGym(id: 'gym-cerca', lat: myLat - 0.009, lng: myLng);
      await seedProfile(uid: 'vecino', gymId: 'gym-cerca');
      await seedProfile(uid: 'otro', gymId: 'gym-cerca');

      final result = await buildContainer(followRepository: repository)
          .read(suggestedUsersProvider('gym-a').future);

      // `vecino` ya tiene una solicitud pendiente conmigo: está en el inbox,
      // no en sugerencias. La exclusión no mira la dirección de la arista.
      expect(result.map((p) => p.uid), ['otro']);
    });

    test('sin el doc del gym propio no inventa cercanía', () async {
      // El gym no está en la colección: no hay desde dónde medir.
      await seedProfile(uid: 'alguien', gymId: 'gym-cerca');

      final result = await buildContainer(followRepository: repository)
          .read(suggestedUsersProvider('gym-a').future);

      expect(result, isEmpty);
    });
  });
}
