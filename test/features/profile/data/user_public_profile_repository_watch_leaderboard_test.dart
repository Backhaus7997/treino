// #1518 — `watchLeaderboard` es la versión en vivo de `leaderboard`.
//
// El bug: la lectura puntual se hacía al abrir el board, y la Cloud Function
// que calcula `lifetimeVolumeKg` escribe 1-3 s DESPUÉS del opt-in. El board
// quedaba congelado con el volumen en 0 hasta salir y volver a la pantalla.

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/gyms/domain/gym.dart' show kNoGymId;
import 'package:treino/features/profile/data/user_public_profile_repository.dart';
import 'package:treino/features/profile/domain/user_public_profile.dart';

void main() {
  const gym = 'gym-a';

  late FakeFirebaseFirestore firestore;
  late UserPublicProfileRepository repo;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    repo = UserPublicProfileRepository(firestore: firestore);
  });

  test(
      're-emite cuando la función escribe el volumen después de la primera '
      'lectura', () async {
    await repo.set(const UserPublicProfile(
      uid: 'me',
      gymId: gym,
      rankingOptIn: true,
    ));

    final emissions = <num>[];
    final sub = repo
        .watchLeaderboard(gymId: gym, metricField: 'lifetimeVolumeKg')
        .listen((board) => emissions.add(board.single.lifetimeVolumeKg));
    addTearDown(sub.cancel);

    await pumpEventQueue();
    expect(emissions, [0], reason: 'primera lectura: el default del modelo');

    // Lo que hace `rankingAggregateOnOptIn` vía Admin SDK.
    await firestore
        .collection('userPublicProfiles')
        .doc('me')
        .update({'lifetimeVolumeKg': 66057.5});
    await pumpEventQueue();

    expect(emissions, [0, 66057.5]);
  });

  test('la lectura puntual NO se entera: es lo que congelaba el board',
      () async {
    await repo.set(const UserPublicProfile(
      uid: 'me',
      gymId: gym,
      rankingOptIn: true,
    ));

    final before = await repo.leaderboard(
      gymId: gym,
      metricField: 'lifetimeVolumeKg',
    );
    await firestore
        .collection('userPublicProfiles')
        .doc('me')
        .update({'lifetimeVolumeKg': 66057.5});

    expect(before.single.lifetimeVolumeKg, 0);
  });

  test('mismo orden y mismo filtro que leaderboard()', () async {
    await repo.set(const UserPublicProfile(
      uid: 'a',
      gymId: gym,
      rankingOptIn: true,
      lifetimeVolumeKg: 500,
    ));
    await repo.set(const UserPublicProfile(
      uid: 'b',
      gymId: gym,
      rankingOptIn: true,
      lifetimeVolumeKg: 900,
    ));
    // Sin opt-in y de otro gym: afuera.
    await repo.set(const UserPublicProfile(
      uid: 'c',
      gymId: gym,
      rankingOptIn: false,
      lifetimeVolumeKg: 9999,
    ));
    await repo.set(const UserPublicProfile(
      uid: 'd',
      gymId: 'gym-b',
      rankingOptIn: true,
      lifetimeVolumeKg: 9999,
    ));

    final live = await repo
        .watchLeaderboard(gymId: gym, metricField: 'lifetimeVolumeKg')
        .first;
    final once = await repo.leaderboard(
      gymId: gym,
      metricField: 'lifetimeVolumeKg',
    );

    expect(live.map((p) => p.uid), ['b', 'a']);
    expect(live.map((p) => p.uid), once.map((p) => p.uid));
  });

  test('sin gym real no hay board ni listener', () async {
    expect(
      await repo
          .watchLeaderboard(gymId: '', metricField: 'lifetimeVolumeKg')
          .toList(),
      [<UserPublicProfile>[]],
    );
    expect(
      await repo
          .watchLeaderboard(gymId: kNoGymId, metricField: 'lifetimeVolumeKg')
          .toList(),
      [<UserPublicProfile>[]],
    );
  });
}
