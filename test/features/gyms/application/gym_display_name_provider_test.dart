import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/features/gyms/application/gym_display_name_provider.dart';
import 'package:treino/features/gyms/application/places_providers.dart';
import 'package:treino/features/gyms/data/resolve_gym_place_service.dart';
import 'package:treino/features/gyms/application/gym_providers.dart';
import 'package:treino/features/gyms/data/gym_repository.dart';
import 'package:treino/features/profile/application/user_providers.dart'
    show firestoreProvider;

class _MockResolve extends Mock implements ResolveGymPlaceService {}

void main() {
  late FakeFirebaseFirestore firestore;
  late _MockResolve resolver;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    resolver = _MockResolve();
  });

  Future<void> seedGym(String id, String name, String source) =>
      firestore.collection('gyms').doc(id).set({
        'name': name,
        'lat': -34.6,
        'lng': -58.4,
        'geohash': '6d6m7',
        'source': source,
        'createdAt': Timestamp.fromDate(DateTime.utc(2026, 1, 1)),
      });

  ProviderContainer container() {
    final c = ProviderContainer(overrides: [
      firestoreProvider.overrideWithValue(firestore),
      gymRepositoryProvider
          .overrideWithValue(GymRepository(firestore: firestore)),
      resolveGymPlaceServiceProvider.overrideWithValue(resolver),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  test('null, vacío y el centinela no-gym dan vacío sin consultar nada',
      () async {
    final c = container();
    expect(await c.read(gymDisplayNameProvider(null).future), '');
    expect(await c.read(gymDisplayNameProvider('').future), '');
    expect(await c.read(gymDisplayNameProvider('no-gym').future), '');
    verifyZeroInteractions(resolver);
  });

  test('gym de Places: muestra el nombre de Google EN VIVO, no el guardado',
      () async {
    await seedGym('ChIJ_1', 'Gimnasio', 'google-places');
    when(() => resolver.fetchDisplayName('ChIJ_1'))
        .thenAnswer((_) async => 'SportClub Belgrano');

    final c = container();
    expect(await c.read(gymDisplayNameProvider('ChIJ_1').future),
        'SportClub Belgrano');

    // Nunca se persiste: el doc sigue con el marcador.
    final doc = await firestore.collection('gyms').doc('ChIJ_1').get();
    expect(doc.data()!['name'], 'Gimnasio');
  });

  test('gym de Places con el pedido caído: cae al nombre guardado', () async {
    await seedGym('ChIJ_1', 'Gimnasio', 'google-places');
    when(() => resolver.fetchDisplayName('ChIJ_1'))
        .thenThrow(const ResolveGymPlaceFailure$Unknown());

    final c = container();
    expect(await c.read(gymDisplayNameProvider('ChIJ_1').future), 'Gimnasio');
  });

  test('gym de Places con Google sin nombre: cae al guardado', () async {
    await seedGym('ChIJ_1', 'Gimnasio', 'google-places');
    when(() => resolver.fetchDisplayName('ChIJ_1'))
        .thenAnswer((_) async => null);

    final c = container();
    expect(await c.read(gymDisplayNameProvider('ChIJ_1').future), 'Gimnasio');
  });

  test('gym sembrado: usa el nombre guardado y no llama a Google', () async {
    await seedGym('smart-fit', 'SmartFit - Palermo', 'seed');

    final c = container();
    expect(await c.read(gymDisplayNameProvider('smart-fit').future),
        'SmartFit - Palermo');
    verifyZeroInteractions(resolver);
  });

  test('gym inexistente: vacío', () async {
    final c = container();
    expect(await c.read(gymDisplayNameProvider('fantasma').future), '');
  });

  test('un nombre vivo se cachea: el segundo consumidor no vuelve a pedirlo',
      () async {
    await seedGym('ChIJ_1', 'Gimnasio', 'google-places');
    when(() => resolver.fetchDisplayName('ChIJ_1'))
        .thenAnswer((_) async => 'Iron Box');

    final c = container();
    expect(await c.read(gymDisplayNameProvider('ChIJ_1').future), 'Iron Box');
    expect(await c.read(gymDisplayNameProvider('ChIJ_1').future), 'Iron Box');
    verify(() => resolver.fetchDisplayName('ChIJ_1')).called(1);
  });
}
