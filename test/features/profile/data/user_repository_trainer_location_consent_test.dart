import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/coach/domain/trainer_location.dart';
import 'package:treino/features/profile/data/user_repository.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';

// ignore_for_file: avoid_dynamic_calls

/// consentimiento-legal-versionado — R6, R8, T1.
///
/// Mirror de `user_repository_trainer_dual_write_test.dart`, mismo helper
/// `seedDoc` + `FakeFirebaseFirestore`. Cubre el gate de consentimiento
/// efectivo sobre el subset público de ubicación (R6) y las dos operaciones
/// explícitas de grant/revoke (R8, T1).
void main() {
  late FakeFirebaseFirestore firestore;
  late UserRepository repo;

  /// Seeds a minimal `users/{uid}` doc, sin consentimiento de ubicación.
  Future<void> seedDoc(String uid) async {
    final now = DateTime.utc(2026, 1, 1);
    final profile = UserProfile(
      uid: uid,
      email: 'seed@test.com',
      displayName: null,
      role: UserRole.trainer,
      createdAt: now,
      updatedAt: now,
    );
    await firestore.collection('users').doc(uid).set(profile.toJson());
  }

  /// Seeds `users/{uid}` con `trainerLocationConsentAt` ya guardado — el
  /// caso "consentimiento efectivo = lo que ya está en el doc", no en el
  /// partial de esta escritura.
  Future<void> seedDocWithConsent(String uid, {DateTime? consentAt}) async {
    final now = DateTime.utc(2026, 1, 1);
    final profile = UserProfile(
      uid: uid,
      email: 'seed@test.com',
      displayName: null,
      role: UserRole.trainer,
      createdAt: now,
      updatedAt: now,
      trainerLocationConsentAt: consentAt ?? DateTime.utc(2026, 1, 1),
      trainerLocationConsentPromptedAt: consentAt ?? DateTime.utc(2026, 1, 1),
    );
    await firestore.collection('users').doc(uid).set(profile.toJson());
  }

  setUp(() {
    firestore = FakeFirebaseFirestore();
    repo = UserRepository(firestore: firestore);
  });

  // ---------------------------------------------------------------------------
  // R6 — el subset público de ubicación exige consentimiento efectivo AL
  // MOMENTO DE ESCRIBIR.
  // ---------------------------------------------------------------------------
  group('R6: location publication requires effective consent at write time',
      () {
    test(
        '4.1: consentAt==null → trainerPublicProfiles NO recibe claves de '
        'ubicación, pero SÍ recibe bio/rate/offersOnline (anti-republish, '
        'descalifica la opción (b))', () async {
      await seedDoc('trainer-noconsent');

      await repo.update('trainer-noconsent', {
        'trainerLocations': [
          {
            'id': 'loc-1',
            'type': 'custom',
            'gymId': null,
            'customLabel': 'Mi estudio',
            'lat': -34.6,
            'lng': -58.4,
            'geohash': '69y7w',
          },
        ],
        'trainerGeohashes': ['69y7w'],
        'trainerBio': 'Especialista en fuerza',
        'trainerMonthlyRate': 8000,
        'trainerOffersOnline': true,
      });

      final snap = await firestore
          .collection('trainerPublicProfiles')
          .doc('trainer-noconsent')
          .get();
      expect(snap.exists, isTrue);
      final data = snap.data()!;

      // Sin consentimiento, las claves de ubicación NO se propagan.
      expect(data.containsKey('trainerLocations'), isFalse);
      expect(data.containsKey('trainerGeohashes'), isFalse);

      // El resto del subset SÍ fluye — el gate es sólo sobre ubicación.
      expect(data['trainerBio'], equals('Especialista en fuerza'));
      expect(data['trainerMonthlyRate'], equals(8000));
      expect(data['trainerOffersOnline'], isTrue);
    });

    test(
        '4.2: consentAt ya guardado (no en el partial) → trainerPublicProfiles '
        'SÍ recibe trainerLocations (consentimiento efectivo = partial sobre '
        'lo guardado)', () async {
      await seedDocWithConsent('trainer-hasconsent');

      await repo.update('trainer-hasconsent', {
        'trainerLocations': [
          {
            'id': 'loc-2',
            'type': 'gym',
            'gymId': 'megatlon-belgrano',
            'customLabel': null,
            'lat': -34.5598,
            'lng': -58.4615,
            'geohash': '69y7w',
          },
        ],
        'trainerGeohashes': ['69y7w'],
      });

      final snap = await firestore
          .collection('trainerPublicProfiles')
          .doc('trainer-hasconsent')
          .get();
      expect(snap.exists, isTrue);
      final data = snap.data()!;
      expect((data['trainerLocations'] as List).length, equals(1));
      expect(data['trainerGeohashes'], equals(['69y7w']));
    });
  });

  // ---------------------------------------------------------------------------
  // R8 / T1 — grant/revoke son operaciones explícitas, con efectos
  // asimétricos y deterministas sobre los dos espejos.
  // ---------------------------------------------------------------------------
  group('R8/T1: grantTrainerLocationConsent / revokeTrainerLocationConsent',
      () {
    const loc = TrainerLocation(
      id: 'loc-1',
      type: TrainerLocationType.gym,
      gymId: 'megatlon-belgrano',
      lat: -34.5598,
      lng: -58.4615,
      geohash: '69y7w',
    );

    /// Seeds a trainer WITH stored locations + offersOnline, sin
    /// consentimiento — el punto de partida típico antes de que el sheet
    /// pida consentimiento por primera vez.
    Future<void> seedTrainerWithLocations(String uid) async {
      final now = DateTime.utc(2026, 1, 1);
      final profile = UserProfile(
        uid: uid,
        email: 'seed@test.com',
        displayName: null,
        role: UserRole.trainer,
        createdAt: now,
        updatedAt: now,
        trainerLocations: const [loc],
        trainerGeohashes: const ['69y7w'],
        trainerOffersOnline: true,
      );
      await firestore.collection('users').doc(uid).set(profile.toJson());
    }

    test(
        '5.1: revokeTrainerLocationConsent no lanza y users/{uid} '
        '.trainerLocations/.trainerOffersOnline quedan intactos — el partial '
        'sólo lleva las 2 claves de consentimiento (cierra el guard-gap)',
        () async {
      await seedTrainerWithLocations('trainer-revoke-1');

      await expectLater(
        repo.revokeTrainerLocationConsent('trainer-revoke-1'),
        completes,
      );

      final snap =
          await firestore.collection('users').doc('trainer-revoke-1').get();
      final data = snap.data()!;
      expect((data['trainerLocations'] as List).length, equals(1));
      expect(data['trainerOffersOnline'], isTrue);
      expect(data['trainerLocationConsentAt'], isNull);
      expect(data['trainerLocationConsentPromptedAt'], isNotNull);
    });

    test(
        '5.2: tras revocar, trainerPublicProfiles pierde las 5 claves de '
        'ubicación y trainerOffersOnline queda intacto', () async {
      await seedTrainerWithLocations('trainer-revoke-2');
      // trainerPublicProfiles ya existe con offersOnline publicado — el
      // camino normal de un PF que ya guardó su form antes. El PF ya estaba
      // consentido y publicado antes de revocar.
      await repo.update('trainer-revoke-2', {'trainerOffersOnline': true});
      await repo.grantTrainerLocationConsent('trainer-revoke-2');

      await repo.revokeTrainerLocationConsent('trainer-revoke-2');

      final snap = await firestore
          .collection('trainerPublicProfiles')
          .doc('trainer-revoke-2')
          .get();
      final data = snap.data()!;
      expect(data['trainerLocations'], isEmpty);
      expect(data['trainerGeohashes'], isEmpty);
      expect(data['trainerLatitude'], isNull);
      expect(data['trainerLongitude'], isNull);
      expect(data['trainerGeohash'], isNull);
      // trainerOffersOnline NO es una clave de ubicación — no se toca.
      expect(data['trainerOffersOnline'], isTrue);
    });

    test(
        '5.3: grantTrainerLocationConsent re-espeja las trainerLocations ya '
        'guardadas en users/ — no sólo el timestamp (evita "consentido pero '
        'invisible")', () async {
      await seedTrainerWithLocations('trainer-grant-1');

      await repo.grantTrainerLocationConsent('trainer-grant-1');

      final usersSnap =
          await firestore.collection('users').doc('trainer-grant-1').get();
      expect(usersSnap.data()!['trainerLocationConsentAt'], isNotNull);
      expect(
        usersSnap.data()!['trainerLocationConsentPromptedAt'],
        isNotNull,
      );

      final publicSnap = await firestore
          .collection('trainerPublicProfiles')
          .doc('trainer-grant-1')
          .get();
      expect(publicSnap.exists, isTrue);
      final publicData = publicSnap.data()!;
      expect((publicData['trainerLocations'] as List).length, equals(1));
      expect(publicData['trainerGeohashes'], equals(['69y7w']));
    });
  });
}
