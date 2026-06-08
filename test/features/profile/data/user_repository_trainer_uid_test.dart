import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/profile/data/user_repository.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';

// ignore_for_file: avoid_dynamic_calls

/// Tests for ADR-TPO-001: uid threaded into _trainerPublicSubsetFromPartial.
///
/// SCENARIO-688: First-time trainer save writes uid to trainerPublicProfiles.
///
/// REQ-TPO-DATA-001.
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

        final snap = await firestore
            .collection('trainerPublicProfiles')
            .doc(uid)
            .get();

        expect(snap.exists, isTrue);
        expect(snap.data()!['uid'], equals(uid));
        expect(snap.data()!['trainerBio'], equals('hello'));
      },
    );
  });
}
