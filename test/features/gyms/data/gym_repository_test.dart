import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/gyms/data/gym_repository.dart';
import 'package:treino/features/gyms/domain/gym.dart';
import 'package:treino/features/gyms/domain/gym_source.dart';

// ignore_for_file: avoid_dynamic_calls

Map<String, Object?> _gymDoc({
  required String name,
  required double lat,
  required double lng,
  String? address,
  String source = 'seed',
  String? createdBy,
}) =>
    {
      'name': name,
      'address': address,
      'lat': lat,
      'lng': lng,
      'geohash': '6d6m7', // fake — tests del repo no necesitan geohash real
      'source': source,
      'createdBy': createdBy,
      'createdAt': Timestamp.fromDate(DateTime.utc(2026, 1, 1)),
    };

void main() {
  late FakeFirebaseFirestore firestore;
  late GymRepository repo;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    repo = GymRepository(firestore: firestore);
  });

  group('GymRepository.listAll', () {
    test('devuelve lista vacía cuando no hay gyms', () async {
      expect(await repo.listAll(), isEmpty);
    });

    test('devuelve todos los gyms del catálogo', () async {
      await firestore.collection('gyms').doc('gym-1').set(
            _gymDoc(name: 'Megatlon Belgrano', lat: -34.55, lng: -58.46),
          );
      await firestore.collection('gyms').doc('gym-2').set(
            _gymDoc(name: 'SmartFit Caballito', lat: -34.61, lng: -58.44),
          );

      final all = await repo.listAll();
      expect(all, hasLength(2));
      expect(all.map((g) => g.id).toSet(), {'gym-1', 'gym-2'});
      expect(all.first.source, equals(GymSource.seed));
    });

    test('inyecta el doc id como Gym.id', () async {
      await firestore.collection('gyms').doc('mi-id-custom').set(
            _gymDoc(name: 'X', lat: 0, lng: 0),
          );
      final all = await repo.listAll();
      expect(all.single.id, 'mi-id-custom');
    });

    test('salta un doc malformado en vez de romper el catálogo entero',
        () async {
      // Doc válido.
      await firestore.collection('gyms').doc('ok-1').set(
            _gymDoc(name: 'Megatlon Belgrano', lat: -34.55, lng: -58.46),
          );
      // Doc malformado: lat guardado como String → Gym.fromJson lanza al
      // castear. Antes del fix esto abortaba todo listAll().
      await firestore.collection('gyms').doc('broken').set({
        ..._gymDoc(name: 'Corrupto', lat: 0, lng: 0),
        'lat': 'no-soy-un-double',
      });
      await firestore.collection('gyms').doc('ok-2').set(
            _gymDoc(name: 'SmartFit Caballito', lat: -34.61, lng: -58.44),
          );

      final all = await repo.listAll();
      expect(all.map((g) => g.id).toSet(), {'ok-1', 'ok-2'});
    });
  });

  group('GymRepository.getById', () {
    test('devuelve null cuando el gym no existe', () async {
      expect(await repo.getById('nope'), isNull);
    });

    test('devuelve el gym cuando existe', () async {
      await firestore.collection('gyms').doc('gym-x').set(
            _gymDoc(
              name: 'Sieger Gym',
              lat: -31.41,
              lng: -64.19,
              source: 'self-service',
              createdBy: 'trainer-uid-1',
            ),
          );
      final gym = await repo.getById('gym-x');
      expect(gym, isNotNull);
      expect(gym!.name, 'Sieger Gym');
      expect(gym.source, GymSource.selfService);
      expect(gym.createdBy, 'trainer-uid-1');
    });
  });

  group('GymRepository.getByIds', () {
    test('input vacío → lista vacía (sin I/O)', () async {
      expect(await repo.getByIds(const []), isEmpty);
    });

    test('devuelve solo los gyms encontrados (ignora ids inexistentes)',
        () async {
      await firestore.collection('gyms').doc('found-1').set(
            _gymDoc(name: 'A', lat: 0, lng: 0),
          );
      await firestore.collection('gyms').doc('found-2').set(
            _gymDoc(name: 'B', lat: 0, lng: 0),
          );

      final gyms = await repo.getByIds(['found-1', 'missing', 'found-2']);
      expect(gyms.map((g) => g.id).toSet(), {'found-1', 'found-2'});
    });
  });

  group('GymRepository.upsert', () {
    test('escribe gyms/{gym.id} con merge:true (crea si no existe)', () async {
      final gym = Gym(
        id: 'ChIJ_place_1',
        name: 'SportClub Belgrano',
        address: 'Cabildo 1789, CABA',
        lat: -34.5598,
        lng: -58.4615,
        geohash: '6d6m7',
        source: GymSource.googlePlaces,
        createdAt: DateTime.utc(2026, 1, 1),
      );

      await repo.upsert(gym);

      final snap = await firestore.collection('gyms').doc('ChIJ_place_1').get();
      expect(snap.exists, isTrue);
      expect(snap.data()!['name'], 'SportClub Belgrano');
      expect(snap.data()!['source'], 'google-places');
    });

    test('no pisa campos existentes fuera del doc escrito (merge real)',
        () async {
      await firestore.collection('gyms').doc('gym-x').set({
        ..._gymDoc(name: 'Old Name', lat: 0, lng: 0),
        'extraLegacyField': 'keep-me',
      });

      final gym = Gym(
        id: 'gym-x',
        name: 'Updated Name',
        lat: 1,
        lng: 2,
        geohash: 'abcde',
        source: GymSource.googlePlaces,
        createdAt: DateTime.utc(2026, 1, 1),
      );
      await repo.upsert(gym);

      final snap = await firestore.collection('gyms').doc('gym-x').get();
      expect(snap.data()!['name'], 'Updated Name');
      expect(snap.data()!['extraLegacyField'], 'keep-me');
    });
  });
}
