import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/gyms/domain/gym.dart';
import 'package:treino/features/gyms/domain/gym_display_name.dart';
import 'package:treino/features/gyms/domain/gym_source.dart';

// ---------------------------------------------------------------------------
// gyms-foundation Phase 3 — safe fallback for the composed brand-branch label.
// Replaces `feed/domain/gym_name.dart`'s hardcoded `_kGymNames` map +
// `gymNameFromId`. The real display name now comes from either:
//   - `Gym.name` (already the composed "Brand - Branch" string, resolved via
//     `gymByIdProvider` for single-user DETAIL contexts), or
//   - `UserPublicProfile.gymName` (denormalized, for LIST contexts).
// Both paths funnel through these two pure helpers so every call site shares
// one non-crashing fallback rule (SCENARIO-528..531 — covers spec req 3).
// ---------------------------------------------------------------------------

Gym _gym({
  String id = 'sportclub-belgrano',
  String name = 'SportClub - Belgrano',
  GymSource source = GymSource.seed,
}) =>
    Gym(
      id: id,
      name: name,
      lat: -34.56,
      lng: -58.45,
      geohash: 'abc123',
      source: source,
      createdAt: DateTime.utc(2026, 1, 1),
    );

void main() {
  group('gymDisplayNameFromGym (detail contexts, gymByIdProvider)', () {
    test('SCENARIO-528: resolved Gym → its composed name', () {
      expect(
        gymDisplayNameFromGym(_gym(name: 'SportClub - Belgrano')),
        equals('SportClub - Belgrano'),
      );
    });

    test('el marcador de Places NUNCA es un nombre: da vacío', () {
      expect(
        gymDisplayNameFromGym(
          _gym(name: kGymPlaceholderName, source: GymSource.googlePlaces),
        ),
        isEmpty,
      );
    });

    test('un gym que NO es de Places y se llama «Gimnasio» conserva su nombre',
        () {
      expect(
        gymDisplayNameFromGym(_gym(name: kGymPlaceholderName)),
        equals(kGymPlaceholderName),
      );
    });

    test('SCENARIO-529: null Gym (unresolvable id) → empty string, no throw',
        () {
      expect(gymDisplayNameFromGym(null), equals(''));
    });
  });

  group('gymDisplayNameFromDenormalized (list contexts, profile.gymName)', () {
    test('SCENARIO-530: non-empty denormalized gymName → returned as-is', () {
      expect(
        gymDisplayNameFromDenormalized('SmartFit - Palermo'),
        equals('SmartFit - Palermo'),
      );
    });

    test('SCENARIO-531: null/empty denormalized gymName → empty string', () {
      expect(gymDisplayNameFromDenormalized(null), equals(''));
      expect(gymDisplayNameFromDenormalized(''), equals(''));
    });
  });
}
