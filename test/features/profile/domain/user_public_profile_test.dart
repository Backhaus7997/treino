import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/profile/domain/user_public_profile.dart';

void main() {
  // ─────────────────────────────────────────────────────────────────────────
  // SCENARIO-252: Model round-trip serialization
  // ─────────────────────────────────────────────────────────────────────────
  group('UserPublicProfile', () {
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
