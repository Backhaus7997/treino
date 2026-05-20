import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/profile/data/user_repository.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';

// ignore_for_file: avoid_dynamic_calls

/// Tests for the trainer dual-write extension added in coach-discovery (PR1).
///
/// SCENARIO-423: When update() receives a partial with ANY trainer public field,
///   the WriteBatch writes to BOTH `users/{uid}` AND `trainerPublicProfiles/{uid}`.
/// SCENARIO-424: When update() receives a partial with ONLY non-trainer fields,
///   only `users/{uid}` is written — `trainerPublicProfiles/{uid}` is NOT touched.
void main() {
  late FakeFirebaseFirestore firestore;
  late UserRepository repo;

  /// Seeds a minimal `users/{uid}` doc.
  Future<void> seedDoc(String uid) async {
    final now = DateTime.utc(2026, 1, 1);
    final profile = UserProfile(
      uid: uid,
      email: 'seed@test.com',
      displayName: null,
      role: UserRole.athlete,
      createdAt: now,
      updatedAt: now,
    );
    await firestore.collection('users').doc(uid).set(profile.toJson());
  }

  setUp(() {
    firestore = FakeFirebaseFirestore();
    repo = UserRepository(firestore: firestore);
  });

  // ---------------------------------------------------------------------------
  // SCENARIO-423 — trainer field triggers dual-write to trainerPublicProfiles
  // ---------------------------------------------------------------------------
  group('UserRepository trainer dual-write (trainerPublicProfiles)', () {
    test(
        'SCENARIO-423a: update with trainerSpecialty writes to '
        'trainerPublicProfiles/{uid}', () async {
      await seedDoc('trainer-1');

      await repo.update('trainer-1', {'trainerSpecialty': 'yoga'});

      final snap = await firestore
          .collection('trainerPublicProfiles')
          .doc('trainer-1')
          .get();
      expect(snap.exists, isTrue);
      expect(snap.data()!['trainerSpecialty'], equals('yoga'));
    });

    test(
        'SCENARIO-423b: update with trainerGeohash writes to '
        'trainerPublicProfiles/{uid}', () async {
      await seedDoc('trainer-2');

      await repo.update('trainer-2', {'trainerGeohash': 's621h'});

      final snap = await firestore
          .collection('trainerPublicProfiles')
          .doc('trainer-2')
          .get();
      expect(snap.exists, isTrue);
      expect(snap.data()!['trainerGeohash'], equals('s621h'));
    });

    test(
        'SCENARIO-423c: update with trainerMonthlyRate writes to '
        'trainerPublicProfiles/{uid}', () async {
      await seedDoc('trainer-3');

      await repo.update('trainer-3', {'trainerMonthlyRate': 50});

      final snap = await firestore
          .collection('trainerPublicProfiles')
          .doc('trainer-3')
          .get();
      expect(snap.exists, isTrue);
      expect(snap.data()!['trainerMonthlyRate'], equals(50));
    });

    test(
        'SCENARIO-423d: update with trainerBio writes to '
        'trainerPublicProfiles/{uid}', () async {
      await seedDoc('trainer-4');

      await repo.update('trainer-4', {'trainerBio': 'Expert trainer'});

      final snap = await firestore
          .collection('trainerPublicProfiles')
          .doc('trainer-4')
          .get();
      expect(snap.exists, isTrue);
      expect(snap.data()!['trainerBio'], equals('Expert trainer'));
    });

    test(
        'SCENARIO-423e: update with displayName writes to BOTH '
        'userPublicProfiles AND trainerPublicProfiles', () async {
      await seedDoc('trainer-5');

      await repo.update('trainer-5', {'displayName': 'Coach María'});

      final pubSnap = await firestore
          .collection('userPublicProfiles')
          .doc('trainer-5')
          .get();
      expect(pubSnap.exists, isTrue);
      expect(pubSnap.data()!['displayName'], equals('Coach María'));

      final trainerSnap = await firestore
          .collection('trainerPublicProfiles')
          .doc('trainer-5')
          .get();
      expect(trainerSnap.exists, isTrue);
      expect(trainerSnap.data()!['displayName'], equals('Coach María'));
    });

    test(
        'SCENARIO-423f: trainerPublicProfiles doc gets only the trainer-public '
        'field subset — no private fields leaked', () async {
      await seedDoc('trainer-6');

      await repo.update('trainer-6', {
        'trainerSpecialty': 'running',
        'trainerGeohash': 'aaaaa',
        'trainerLatitude': -34.6,
        'trainerLongitude': -58.4,
      });

      final snap = await firestore
          .collection('trainerPublicProfiles')
          .doc('trainer-6')
          .get();
      final data = snap.data()!;

      // Trainer fields are present
      expect(data['trainerSpecialty'], equals('running'));
      expect(data['trainerGeohash'], equals('aaaaa'));
      expect(data['trainerLatitude'], equals(-34.6));
      expect(data['trainerLongitude'], equals(-58.4));

      // Private fields must NOT be present
      expect(data.containsKey('email'), isFalse);
      expect(data.containsKey('bodyWeightKg'), isFalse);
      expect(data.containsKey('gymId'), isFalse);
      expect(data.containsKey('heightCm'), isFalse);
      expect(data.containsKey('role'), isFalse);
      expect(data.containsKey('createdAt'), isFalse);
    });

    test(
        'SCENARIO-423g: update with trainerLatitude and trainerLongitude '
        'writes to trainerPublicProfiles', () async {
      await seedDoc('trainer-7');

      await repo.update('trainer-7', {
        'trainerLatitude': -34.6037,
        'trainerLongitude': -58.3816,
      });

      final snap = await firestore
          .collection('trainerPublicProfiles')
          .doc('trainer-7')
          .get();
      expect(snap.exists, isTrue);
      expect(snap.data()!['trainerLatitude'], closeTo(-34.6037, 0.0001));
      expect(snap.data()!['trainerLongitude'], closeTo(-58.3816, 0.0001));
    });

    // ---------------------------------------------------------------------------
    // SCENARIO-424 — non-trainer fields do NOT touch trainerPublicProfiles
    // ---------------------------------------------------------------------------

    test(
        'SCENARIO-424a: update with only gymId does NOT write to '
        'trainerPublicProfiles', () async {
      await seedDoc('athlete-1');

      await repo.update('athlete-1', {'gymId': 'gym-xyz'});

      final snap = await firestore
          .collection('trainerPublicProfiles')
          .doc('athlete-1')
          .get();
      expect(snap.exists, isFalse);
    });

    test(
        'SCENARIO-424b: update with only bodyWeightKg does NOT write to '
        'trainerPublicProfiles', () async {
      await seedDoc('athlete-2');

      await repo.update('athlete-2', {'bodyWeightKg': 75.5});

      final snap = await firestore
          .collection('trainerPublicProfiles')
          .doc('athlete-2')
          .get();
      expect(snap.exists, isFalse);
    });

    test(
        'SCENARIO-424c: update with only experienceLevel does NOT write to '
        'trainerPublicProfiles', () async {
      await seedDoc('athlete-3');

      await repo.update('athlete-3', {'experienceLevel': 'beginner'});

      final snap = await firestore
          .collection('trainerPublicProfiles')
          .doc('athlete-3')
          .get();
      expect(snap.exists, isFalse);
    });

    // ---------------------------------------------------------------------------
    // Existing userPublicProfiles behavior MUST remain unchanged
    // ---------------------------------------------------------------------------

    test(
        'existing userPublicProfiles dual-write is unaffected — displayName '
        'still propagates with lowercase derivation', () async {
      await seedDoc('compat-1');
      await firestore.collection('userPublicProfiles').doc('compat-1').set({
        'uid': 'compat-1',
        'displayName': null,
        'displayNameLowercase': null,
        'avatarUrl': null,
        'gymId': null,
      });

      await repo.update('compat-1', {'displayName': 'Luis'});

      final pubSnap = await firestore
          .collection('userPublicProfiles')
          .doc('compat-1')
          .get();
      expect(pubSnap.data()!['displayName'], equals('Luis'));
      expect(pubSnap.data()!['displayNameLowercase'], equals('luis'));
    });

    test(
        'existing userPublicProfiles dual-write is unaffected — gymId update '
        'still propagates to userPublicProfiles', () async {
      await seedDoc('compat-2');

      await repo.update('compat-2', {'gymId': 'gym-abc'});

      final pubSnap = await firestore
          .collection('userPublicProfiles')
          .doc('compat-2')
          .get();
      expect(pubSnap.exists, isTrue);
      expect(pubSnap.data()!['gymId'], equals('gym-abc'));
    });

    test(
        'trainer update with displayName also derives displayNameLowercase '
        'in trainerPublicProfiles', () async {
      await seedDoc('trainer-lc');

      await repo.update('trainer-lc', {'displayName': 'CARLOS'});

      final trainerSnap = await firestore
          .collection('trainerPublicProfiles')
          .doc('trainer-lc')
          .get();
      expect(trainerSnap.data()!['displayNameLowercase'], equals('carlos'));
    });

    test(
        'avatarUrl update writes to BOTH userPublicProfiles AND '
        'trainerPublicProfiles', () async {
      await seedDoc('trainer-av');

      await repo
          .update('trainer-av', {'avatarUrl': 'https://example.com/img.jpg'});

      final pubSnap = await firestore
          .collection('userPublicProfiles')
          .doc('trainer-av')
          .get();
      expect(
          pubSnap.data()!['avatarUrl'], equals('https://example.com/img.jpg'));

      final trainerSnap = await firestore
          .collection('trainerPublicProfiles')
          .doc('trainer-av')
          .get();
      expect(trainerSnap.data()!['avatarUrl'],
          equals('https://example.com/img.jpg'));
    });
  });
}
