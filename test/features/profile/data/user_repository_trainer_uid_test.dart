import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/profile/data/user_repository.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';

// ignore_for_file: avoid_dynamic_calls

/// Tests for ADR-TPO-001: uid threaded into _trainerPublicSubsetFromPartial.
///
/// SCENARIO-688: First-time trainer save writes uid to trainerPublicProfiles.
/// SCENARIO-689: Re-saving trainer profile is idempotent (uid unchanged).
/// SCENARIO-690: Athlete-only partial does not touch trainerPublicProfiles.
/// SCENARIO-691: averageRating is not included in public profile dual-write.
/// SCENARIO-692: Save with no locations and online=false is rejected.
/// SCENARIO-693: Save with trainerOffersOnline=true and empty locations is accepted.
///
/// REQ-TPO-DATA-001, REQ-TPO-DATA-002, REQ-TPO-DATA-003.
void main() {
  late FakeFirebaseFirestore firestore;
  late UserRepository repo;

  Future<void> seedDoc(String uid) async {
    final now = DateTime.utc(2026, 1, 1);
    final profile = UserProfile(
      uid: uid,
      email: 'seed@test.com',
      displayName: 'Test User',
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

  group('_trainerPublicSubsetFromPartial uid fix (ADR-TPO-001)', () {
    test(
      'SCENARIO-688: first-time trainer save writes uid to trainerPublicProfiles',
      () async {
        const uid = 'user_a';
        await seedDoc(uid);

        await repo.update(uid, {
          'trainerBio': 'hello',
          'trainerSpecialty': 'crossfit',
          'trainerOffersOnline': true,
        });

        final snap =
            await firestore.collection('trainerPublicProfiles').doc(uid).get();

        expect(snap.exists, isTrue);
        expect(snap.data()!['uid'], equals(uid));
        expect(snap.data()!['trainerBio'], equals('hello'));
      },
    );

    test(
      'SCENARIO-689: re-saving trainer profile is idempotent — uid unchanged',
      () async {
        const uid = 'user_idempotent';
        await seedDoc(uid);

        // First save
        await repo.update(uid, {
          'trainerBio': 'hello',
          'trainerOffersOnline': true,
        });

        // Second save with different bio
        await repo.update(uid, {
          'trainerBio': 'updated',
          'trainerOffersOnline': true,
        });

        final snap =
            await firestore.collection('trainerPublicProfiles').doc(uid).get();

        expect(snap.data()!['uid'], equals(uid));
        expect(snap.data()!['trainerBio'], equals('updated'));
      },
    );

    test(
      'SCENARIO-690: partial with only athlete fields does NOT write to '
      'trainerPublicProfiles',
      () async {
        const uid = 'user_athlete_only';
        await seedDoc(uid);

        await repo.update(uid, {'bodyWeightKg': 70.0});

        final snap =
            await firestore.collection('trainerPublicProfiles').doc(uid).get();

        expect(
          snap.exists,
          isFalse,
          reason:
              'athlete-only partial must not trigger a trainerPublicProfiles write',
        );
      },
    );

    test(
      'SCENARIO-691: partial containing averageRating does NOT include '
      'averageRating in trainerPublicProfiles subset (ADR-RV-005)',
      () async {
        const uid = 'user_avg_rating';
        await seedDoc(uid);

        // Includes a trainer field to trigger dual-write, plus averageRating
        await repo.update(uid, {
          'trainerBio': 'bio text',
          'trainerOffersOnline': true,
          'averageRating': 4.5,
        });

        final snap =
            await firestore.collection('trainerPublicProfiles').doc(uid).get();

        expect(snap.exists, isTrue);
        expect(
          snap.data()!.containsKey('averageRating'),
          isFalse,
          reason:
              'averageRating must not be in _trainerPublicFields — ADR-RV-005',
        );
      },
    );

    test(
      'SCENARIO-692: partial with trainerLocations=[] and '
      'trainerOffersOnline=false throws before any write',
      () async {
        const uid = 'user_guard';
        await seedDoc(uid);

        expect(
          () => repo.update(uid, {
            'trainerLocations': <dynamic>[],
            'trainerOffersOnline': false,
          }),
          throwsA(isA<ArgumentError>()),
        );

        // trainerPublicProfiles doc must NOT exist
        final snap =
            await firestore.collection('trainerPublicProfiles').doc(uid).get();
        expect(snap.exists, isFalse);
      },
    );

    test(
      'SCENARIO-693: partial with trainerOffersOnline=true and empty locations '
      'is accepted (no exception, write proceeds)',
      () async {
        const uid = 'user_online_only';
        await seedDoc(uid);

        // Should NOT throw
        await repo.update(uid, {
          'trainerBio': 'bio',
          'trainerLocations': <dynamic>[],
          'trainerOffersOnline': true,
        });

        final snap =
            await firestore.collection('trainerPublicProfiles').doc(uid).get();
        expect(snap.exists, isTrue);
      },
    );
  });
}
