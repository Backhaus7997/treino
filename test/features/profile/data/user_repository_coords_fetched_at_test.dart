import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/coach/domain/trainer_location.dart';
import 'package:treino/features/profile/data/user_repository.dart';

/// `users/{uid}.trainerLocationsCoordsFetchedAt` lo deriva el repositorio:
/// cualquier escritor de `trainerLocations` (Coach Hub, editor móvil) lo deja
/// consistente sin acordarse de calcularlo.
void main() {
  late FakeFirebaseFirestore firestore;
  late UserRepository repo;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    repo = UserRepository(firestore: firestore);
  });

  TrainerLocation lugar(String id, {String? placeId, DateTime? t}) =>
      TrainerLocation(
        id: id,
        type: TrainerLocationType.custom,
        customLabel: id,
        lat: -34.6,
        lng: -58.4,
        geohash: 'GEOHASH',
        placeId: placeId,
        coordsFetchedAt: t,
      );

  Future<Map<String, Object?>> users() async =>
      (await firestore.collection('users').doc('u1').get()).data()!;

  test('con lugares de Places: queda el coordsFetchedAt MÁS VIEJO', () async {
    final viejo = DateTime.utc(2026, 8, 1);
    final nuevo = DateTime.utc(2026, 9, 20);
    await repo.update('u1', {
      'trainerOffersOnline': true,
      'trainerLocations': [
        lugar('a', placeId: 'P1', t: nuevo).toJson(),
        lugar('b', placeId: 'P2', t: viejo).toJson(),
        lugar('c', t: DateTime.utc(2026, 1, 1)).toJson(), // sin placeId
      ],
    });
    final d = await users();
    expect(d['trainerLocationsCoordsFetchedAt'], isA<Timestamp>());
    expect(
      (d['trainerLocationsCoordsFetchedAt']! as Timestamp).toDate().toUtc(),
      viejo,
    );
  });

  test('sin lugares con placeId: el campo queda en null', () async {
    await repo.update('u1', {
      'trainerOffersOnline': true,
      'trainerLocations': [lugar('a').toJson()],
    });
    final d = await users();
    expect(d.containsKey('trainerLocationsCoordsFetchedAt'), isTrue);
    expect(d['trainerLocationsCoordsFetchedAt'], isNull);
  });

  test('un partial sin trainerLocations no toca el campo', () async {
    final t = DateTime.utc(2026, 8, 1);
    await repo.update('u1', {
      'trainerOffersOnline': true,
      'trainerLocations': [lugar('a', placeId: 'P1', t: t).toJson()],
    });
    await repo.update('u1', {'trainerBio': 'hola'});
    final d = await users();
    expect(
      (d['trainerLocationsCoordsFetchedAt']! as Timestamp).toDate().toUtc(),
      t,
    );
  });

  test('no se espeja a trainerPublicProfiles', () async {
    await repo.update(
      'u1',
      {
        'trainerOffersOnline': true,
        'trainerLocations': [
          lugar('a', placeId: 'P1', t: DateTime.utc(2026, 8, 1)).toJson(),
        ],
      },
      grantLocationConsent: true,
    );
    final pub =
        (await firestore.collection('trainerPublicProfiles').doc('u1').get())
            .data();
    expect(pub, isNotNull);
    expect(pub!.containsKey('trainerLocationsCoordsFetchedAt'), isFalse);
  });
}
