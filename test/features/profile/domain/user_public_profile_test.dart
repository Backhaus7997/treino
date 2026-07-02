import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/profile/domain/user_public_profile.dart';

void main() {
  // ─────────────────────────────────────────────────────────────────────────
  // SCENARIO-252: Model round-trip serialization
  // ─────────────────────────────────────────────────────────────────────────
  group('UserPublicProfile', () {
    // ── SCENARIO-320: New counter fields ────────────────────────────────────
    group('SCENARIO-320 — counter fields', () {
      test(
          'SCENARIO-320a: fromJson with no counter fields → all 4 new fields are null',
          () {
        final json = {
          'uid': 'u1',
          'displayName': 'Ana',
          'displayNameLowercase': 'ana',
          'avatarUrl': null,
          'gymId': null,
        };
        final profile = UserPublicProfile.fromJson(json);
        expect(profile.workoutsCount, isNull);
        expect(profile.racha, isNull);
        expect(profile.followersCount, isNull);
        expect(profile.followingCount, isNull);
      });

      test('SCENARIO-320b: fromJson with all counter fields → values preserved',
          () {
        final json = {
          'uid': 'u1',
          'displayName': 'Ana',
          'displayNameLowercase': 'ana',
          'avatarUrl': null,
          'gymId': null,
          'workoutsCount': 42,
          'racha': 7,
          'followersCount': 100,
          'followingCount': 55,
        };
        final profile = UserPublicProfile.fromJson(json);
        expect(profile.workoutsCount, equals(42));
        expect(profile.racha, equals(7));
        expect(profile.followersCount, equals(100));
        expect(profile.followingCount, equals(55));
      });

      test(
          'SCENARIO-320c: existing non-counter fields preserved when counter fields present',
          () {
        final json = {
          'uid': 'u2',
          'displayName': 'Martín',
          'displayNameLowercase': 'martín',
          'avatarUrl': 'https://x.com/avatar.jpg',
          'gymId': 'gym-001',
          'workoutsCount': 10,
          'racha': 3,
          'followersCount': 20,
          'followingCount': 15,
        };
        final profile = UserPublicProfile.fromJson(json);
        expect(profile.uid, equals('u2'));
        expect(profile.displayName, equals('Martín'));
        expect(profile.displayNameLowercase, equals('martín'));
        expect(profile.avatarUrl, equals('https://x.com/avatar.jpg'));
        expect(profile.gymId, equals('gym-001'));
      });

      test(
          'SCENARIO-320e: negative stored counters clamp to 0 on read '
          '(atomic decrement cannot floor at zero — defensive read guard)', () {
        final json = {
          'uid': 'u1',
          'displayName': 'Ana',
          'followersCount': -1,
          'followingCount': -1,
        };
        final profile = UserPublicProfile.fromJson(json);
        expect(profile.followersCount, equals(0));
        expect(profile.followingCount, equals(0));
      });

      test('SCENARIO-320d: JSON round-trip preserves counter fields', () {
        const profile = UserPublicProfile(
          uid: 'u3',
          displayName: 'Test',
          workoutsCount: 89,
          racha: 14,
          followersCount: 412,
          followingCount: 284,
        );
        final json = profile.toJson();
        final restored = UserPublicProfile.fromJson(json);
        expect(restored.workoutsCount, equals(89));
        expect(restored.racha, equals(14));
        expect(restored.followersCount, equals(412));
        expect(restored.followingCount, equals(284));
      });
    });

    test('SCENARIO-252: JSON round-trip preserves all fields', () {
      const profile = UserPublicProfile(
        uid: 'u1',
        displayName: 'Martín',
        displayNameLowercase: 'martín',
        avatarUrl: null,
        gymId: 'g1',
      );

      final json = profile.toJson();
      final restored = UserPublicProfile.fromJson(json);

      expect(restored, equals(profile));
      expect(restored.uid, equals('u1'));
      expect(restored.displayName, equals('Martín'));
      expect(restored.displayNameLowercase, equals('martín'));
      expect(restored.avatarUrl, isNull);
      expect(restored.gymId, equals('g1'));
    });

    // ── Phase 3 (gyms-foundation) — denormalized gymName ────────────────────
    group('gymName (denormalized brand-branch label)', () {
      test(
          'SCENARIO-521: fromJson without gymName → field is null '
          '(backward-compat for existing docs)', () {
        final json = {
          'uid': 'u1',
          'displayName': 'Ana',
          'gymId': 'sportclub-belgrano',
        };
        final profile = UserPublicProfile.fromJson(json);
        expect(profile.gymName, isNull);
      });

      test('SCENARIO-522: fromJson with gymName → value preserved', () {
        final json = {
          'uid': 'u1',
          'displayName': 'Ana',
          'gymId': 'sportclub-belgrano',
          'gymName': 'SportClub - Belgrano',
        };
        final profile = UserPublicProfile.fromJson(json);
        expect(profile.gymName, equals('SportClub - Belgrano'));
      });

      test('SCENARIO-523: JSON round-trip preserves gymName', () {
        const profile = UserPublicProfile(
          uid: 'u1',
          displayName: 'Ana',
          gymId: 'sportclub-belgrano',
          gymName: 'SportClub - Belgrano',
        );
        final json = profile.toJson();
        final restored = UserPublicProfile.fromJson(json);
        expect(restored.gymName, equals('SportClub - Belgrano'));
        expect(restored, equals(profile));
      });
    });

    // ── rankings Phase 1 — ranking opt-in + metric fields ──────────────────
    group('SCENARIO-RANK-1 — ranking fields', () {
      test(
          'SCENARIO-RANK-1a: fromJson without ranking fields → rankingOptIn '
          'defaults false, lifetimeVolumeKg defaults 0, best<Lift>Kg are null '
          '(backward-compat for existing docs, spec: "Opted-out athlete has '
          'no ranking metrics")', () {
        final json = {
          'uid': 'u1',
          'displayName': 'Ana',
          'displayNameLowercase': 'ana',
          'avatarUrl': null,
          'gymId': null,
        };
        final profile = UserPublicProfile.fromJson(json);
        expect(profile.rankingOptIn, isFalse);
        expect(profile.lifetimeVolumeKg, equals(0));
        expect(profile.bestSquatKg, isNull);
        expect(profile.bestBenchKg, isNull);
        expect(profile.bestDeadliftKg, isNull);
      });

      test(
          'SCENARIO-RANK-1b: fromJson with all ranking fields → values '
          'preserved', () {
        final json = {
          'uid': 'u1',
          'displayName': 'Ana',
          'gymId': 'gym-001',
          'rankingOptIn': true,
          'lifetimeVolumeKg': 12345.5,
          'bestSquatKg': 120.0,
          'bestBenchKg': 90.0,
          'bestDeadliftKg': 160.0,
        };
        final profile = UserPublicProfile.fromJson(json);
        expect(profile.rankingOptIn, isTrue);
        expect(profile.lifetimeVolumeKg, equals(12345.5));
        expect(profile.bestSquatKg, equals(120.0));
        expect(profile.bestBenchKg, equals(90.0));
        expect(profile.bestDeadliftKg, equals(160.0));
      });

      test(
          'SCENARIO-RANK-1c: existing non-ranking fields preserved when '
          'ranking fields present', () {
        final json = {
          'uid': 'u2',
          'displayName': 'Martín',
          'gymId': 'gym-001',
          'rankingOptIn': true,
          'lifetimeVolumeKg': 500,
        };
        final profile = UserPublicProfile.fromJson(json);
        expect(profile.uid, equals('u2'));
        expect(profile.displayName, equals('Martín'));
        expect(profile.gymId, equals('gym-001'));
      });

      test('SCENARIO-RANK-1d: JSON round-trip preserves ranking fields', () {
        const profile = UserPublicProfile(
          uid: 'u3',
          displayName: 'Test',
          rankingOptIn: true,
          lifetimeVolumeKg: 999.5,
          bestSquatKg: 100.0,
          bestBenchKg: 80.0,
          bestDeadliftKg: 140.0,
        );
        final json = profile.toJson();
        final restored = UserPublicProfile.fromJson(json);
        expect(restored.rankingOptIn, isTrue);
        expect(restored.lifetimeVolumeKg, equals(999.5));
        expect(restored.bestSquatKg, equals(100.0));
        expect(restored.bestBenchKg, equals(80.0));
        expect(restored.bestDeadliftKg, equals(140.0));
        expect(restored, equals(profile));
      });

      test(
          'SCENARIO-RANK-1e: default constructor (no args for ranking '
          'fields) → rankingOptIn false, lifetimeVolumeKg 0, best<Lift>Kg '
          'null', () {
        const profile = UserPublicProfile(uid: 'u4');
        expect(profile.rankingOptIn, isFalse);
        expect(profile.lifetimeVolumeKg, equals(0));
        expect(profile.bestSquatKg, isNull);
        expect(profile.bestBenchKg, isNull);
        expect(profile.bestDeadliftKg, isNull);
      });
    });

    // SCENARIO-253: displayNameLowercase auto-derivation is enforced at the
    // write-path layer (UserRepository private helpers), NOT by the model
    // constructor. The model accepts whatever is passed — it is a plain value
    // object. This test documents that contract: the Freezed constructor does
    // NOT auto-derive displayNameLowercase.
    test(
        'SCENARIO-253: model does not auto-derive displayNameLowercase '
        '(derivation is the repository write-path responsibility)', () {
      // The model stores whatever is passed — enforcement is in the repo helpers.
      const profile = UserPublicProfile(
        uid: 'u1',
        displayName: 'Martín Backhaus',
        displayNameLowercase: null, // intentionally not derived here
      );
      // Model does NOT auto-derive — repo helper is responsible.
      expect(profile.displayNameLowercase, isNull);

      // Derived value that the repo helper would produce:
      final derived = profile.displayName?.trim().toLowerCase();
      expect(derived, equals('martín backhaus'));
    });
  });
}
