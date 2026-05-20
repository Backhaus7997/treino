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
