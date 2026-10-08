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

  group('lugares stale (purga de 30 días de Places)', () {
    TrainerLocation vencido(String id, {String? placeId, DateTime? t}) =>
        TrainerLocation(
          id: id,
          type: TrainerLocationType.custom,
          customLabel: id,
          placeId: placeId,
          coordsFetchedAt: t,
          stale: true,
        );

    test(
        'un stale que conserva su fecha (fallo transitorio) cuenta para el '
        'mínimo: el job lo sigue reintentando', () async {
      final viejo = DateTime.utc(2026, 8, 1);
      await repo.update('u1', {
        'trainerOffersOnline': true,
        'trainerLocations': [
          lugar('a', placeId: 'P1', t: DateTime.utc(2026, 9, 20)).toJson(),
          vencido('b', placeId: 'P2', t: viejo).toJson(),
        ],
      });
      expect(
        ((await users())['trainerLocationsCoordsFetchedAt']! as Timestamp)
            .toDate()
            .toUtc(),
        viejo,
      );
    });

    test('un stale SIN fecha (NOT_FOUND) no cuenta: sale de la cola', () async {
      await repo.update('u1', {
        'trainerOffersOnline': true,
        'trainerLocations': [vencido('b', placeId: 'P2').toJson()],
      });
      expect((await users())['trainerLocationsCoordsFetchedAt'], isNull);
    });

    Future<Map<String, Object?>> espejo() async =>
        (await firestore.collection('trainerPublicProfiles').doc('u1').get())
            .data()!;

    test('el espejo público NO recibe un lugar stale ni uno sin coordenadas',
        () async {
      await repo.update(
        'u1',
        {
          'trainerOffersOnline': true,
          'trainerLocations': [
            lugar('vigente', placeId: 'P1', t: DateTime.utc(2026, 9, 20))
                .toJson(),
            vencido('vencido', placeId: 'P2', t: DateTime.utc(2026, 8, 1))
                .toJson(),
            // stale por error del cliente pero con coordenadas viejas
            lugar('con-coords-stale', placeId: 'P3')
                .copyWith(stale: true)
                .toJson(),
          ],
        },
        grantLocationConsent: true,
      );

      final pub = await espejo();
      final ids = (pub['trainerLocations']! as List)
          .map((l) => (l as Map)['id'])
          .toList();
      expect(ids, ['vigente']);
      // El dato del usuario (users/) sí conserva todo, para el reintento.
      final u = await users();
      expect((u['trainerLocations']! as List), hasLength(3));
    });

    test('otorgar consentimiento re-espeja SOLO los lugares con coordenadas',
        () async {
      await firestore.collection('users').doc('u1').set({
        'trainerLocations': [
          lugar('vigente').toJson(),
          vencido('vencido', placeId: 'P2').toJson(),
        ],
        'trainerGeohashes': ['GEOHASH'],
      });

      await repo.grantTrainerLocationConsent('u1');

      final ids = ((await espejo())['trainerLocations']! as List)
          .map((l) => (l as Map)['id'])
          .toList();
      expect(ids, ['vigente']);
    });
  });
}
