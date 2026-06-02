import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/profile/data/user_repository.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';

// ignore_for_file: avoid_dynamic_calls

/// Regression guard for ADR-RV-005.
///
/// `averageRating` and `reviewCount` are CF-write-only aggregate fields on
/// `trainerPublicProfiles/{uid}`. They MUST NOT be included in
/// `UserRepository._trainerPublicFields` (the dual-write whitelist), because
/// any client-side update that happens to include those keys would overwrite
/// the CF-computed aggregate with stale or malicious data.
///
/// This test locks that invariant behaviorally: an `update()` call that
/// contains ONLY `averageRating` or ONLY `reviewCount` must NOT write to
/// `trainerPublicProfiles/{uid}`.
///
/// SCENARIO-578. REQ-RV-DATA-006.
void main() {
  late FakeFirebaseFirestore firestore;
  late UserRepository repo;

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

  group('_trainerPublicFields_excludes_aggregates (ADR-RV-005)', () {
    test(
      'SCENARIO-578: update with averageRating alone does NOT write to '
      'trainerPublicProfiles/{uid}',
      () async {
        const uid = 'trainer-guard-avg';
        await seedDoc(uid);

        // Update with only averageRating — should not trigger dual-write
        await repo.update(uid, {'averageRating': 4.5});

        final snap =
            await firestore.collection('trainerPublicProfiles').doc(uid).get();

        // trainerPublicProfiles doc must NOT exist (not created by the update)
        expect(
          snap.exists,
          isFalse,
          reason: 'averageRating must not be in _trainerPublicFields — '
              'it is a CF-write-only aggregate (ADR-RV-005)',
        );
      },
    );

    test(
      'SCENARIO-578: update with reviewCount alone does NOT write to '
      'trainerPublicProfiles/{uid}',
      () async {
        const uid = 'trainer-guard-count';
        await seedDoc(uid);

        // Update with only reviewCount — should not trigger dual-write
        await repo.update(uid, {'reviewCount': 3});

        final snap =
            await firestore.collection('trainerPublicProfiles').doc(uid).get();

        expect(
          snap.exists,
          isFalse,
          reason: 'reviewCount must not be in _trainerPublicFields — '
              'it is a CF-write-only aggregate (ADR-RV-005)',
        );
      },
    );

    test(
      'SCENARIO-578: update with both averageRating and reviewCount does NOT '
      'write to trainerPublicProfiles/{uid}',
      () async {
        const uid = 'trainer-guard-both';
        await seedDoc(uid);

        await repo.update(uid, {
          'averageRating': 4.2,
          'reviewCount': 7,
        });

        final snap =
            await firestore.collection('trainerPublicProfiles').doc(uid).get();

        expect(snap.exists, isFalse);
      },
    );
  });
}
