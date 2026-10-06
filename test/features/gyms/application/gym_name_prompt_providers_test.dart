import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/gyms/application/gym_name_prompt_providers.dart';
import 'package:treino/features/gyms/application/gym_providers.dart';
import 'package:treino/features/gyms/data/gym_repository.dart';
import 'package:treino/features/gyms/domain/gym.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';

UserProfile _profile({String? gymId}) => UserProfile(
      uid: 'u1',
      email: 'u1@test.com',
      displayName: 'Ana',
      role: UserRole.athlete,
      createdAt: DateTime.utc(2026, 5, 12),
      updatedAt: DateTime.utc(2026, 5, 12),
      gymId: gymId,
    );

Map<String, Object?> _gymDoc({required bool nameNeeded, String? name}) => {
      'name': name ?? 'Gimnasio',
      if (nameNeeded) 'nameNeeded': true,
      'lat': -34.5,
      'lng': -58.4,
      'geohash': '6d6m7',
      'source': 'google-places',
      'createdAt': Timestamp.fromDate(DateTime.utc(2026, 1, 1)),
    };

void main() {
  late FakeFirebaseFirestore firestore;

  setUp(() => firestore = FakeFirebaseFirestore());

  ProviderContainer build(Stream<UserProfile?> profile) {
    final c = ProviderContainer(overrides: [
      userProfileProvider.overrideWith((ref) => profile),
      gymRepositoryProvider
          .overrideWithValue(GymRepository(firestore: firestore)),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  // Mantiene viva la suscripción y deja correr los streams.
  Future<AsyncValue<Gym?>> settle(ProviderContainer c) async {
    final sub = c.listen(gymNamePromptGymProvider, (_, __) {});
    addTearDown(sub.close);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    return c.read(gymNamePromptGymProvider);
  }

  group('GymRepository.watchById', () {
    test('emite el gym y se actualiza en vivo', () async {
      await firestore
          .collection('gyms')
          .doc('g1')
          .set(_gymDoc(nameNeeded: true));
      final repo = GymRepository(firestore: firestore);
      final emitted = <bool?>[];
      final sub =
          repo.watchById('g1').listen((g) => emitted.add(g?.nameNeeded));
      await Future<void>.delayed(Duration.zero);
      await repo.setName('g1', 'Iron Box');
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();
      expect(emitted, [true, false]);
    });

    test('emite null si el doc no existe', () async {
      final repo = GymRepository(firestore: firestore);
      expect(await repo.watchById('nope').first, isNull);
    });
  });

  group('gymNamePromptGymProvider', () {
    test('devuelve el gym cuando el vinculado está nameNeeded', () async {
      await firestore
          .collection('gyms')
          .doc('g1')
          .set(_gymDoc(nameNeeded: true));
      final c = build(Stream.value(_profile(gymId: 'g1')));
      final v = await settle(c);
      expect(v.valueOrNull?.id, 'g1');
    });

    test('es null si el gym ya tiene nombre', () async {
      await firestore
          .collection('gyms')
          .doc('g1')
          .set(_gymDoc(nameNeeded: false, name: 'Iron Box'));
      final c = build(Stream.value(_profile(gymId: 'g1')));
      final v = await settle(c);
      expect(v.hasValue, isTrue);
      expect(v.valueOrNull, isNull);
    });

    test('es null sin gymId', () async {
      final c = build(Stream.value(_profile()));
      final v = await settle(c);
      expect(v.hasValue, isTrue);
      expect(v.valueOrNull, isNull);
    });

    test('es null con el sentinel no-gym', () async {
      final c = build(Stream.value(_profile(gymId: 'no-gym')));
      final v = await settle(c);
      expect(v.hasValue, isTrue);
      expect(v.valueOrNull, isNull);
    });

    test('mientras el perfil carga no es dato', () async {
      final c = build(const Stream<UserProfile?>.empty());
      final v = await settle(c);
      expect(v.hasValue, isFalse);
    });

    test('un gym inexistente es null, no error', () async {
      final c = build(Stream.value(_profile(gymId: 'fantasma')));
      final v = await settle(c);
      expect(v.hasError, isFalse);
      expect(v.valueOrNull, isNull);
    });
  });
}
