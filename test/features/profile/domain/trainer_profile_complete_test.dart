import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/coach/domain/trainer_location.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_profile_trainer_completeness.dart';
import 'package:treino/features/profile/domain/user_role.dart';

/// Pure Dart unit tests for UserProfileTrainerCompleteness extension getter.
///
/// SCENARIO-694: trainerProfileComplete is false when bio is null.
/// SCENARIO-695: trainerProfileComplete is false when specialty is null.
/// SCENARIO-696: trainerProfileComplete is false when monthlyRate is null.
/// SCENARIO-697: trainerProfileComplete is false when locations empty and online=false.
/// SCENARIO-698: trainerProfileComplete is true when all fields set and online=true.
/// SCENARIO-699: trainerProfileComplete is true when all fields set and locations non-empty.
/// SCENARIO-700: trainerProfileComplete is false when all trainer fields null (fresh trainer).
///
/// REQ-TPO-DATA-004.
void main() {
  final DateTime kDate = DateTime.utc(2026, 1, 1);

  UserProfile baseProfile({
    String? trainerBio = 'bio text',
    String? trainerSpecialty = 'crossfit',
    int? trainerMonthlyRate = 50000,
    List<TrainerLocation>? trainerLocations,
    bool trainerOffersOnline = false,
  }) =>
      UserProfile(
        uid: 'trainer-uid',
        email: 'trainer@example.com',
        displayName: 'Test Trainer',
        role: UserRole.trainer,
        createdAt: kDate,
        updatedAt: kDate,
        trainerBio: trainerBio,
        trainerSpecialty: trainerSpecialty,
        trainerMonthlyRate: trainerMonthlyRate,
        trainerLocations: trainerLocations ?? const [],
        trainerOffersOnline: trainerOffersOnline,
      );

  final TrainerLocation kLocation = TrainerLocation(
    id: 'loc-1',
    type: TrainerLocationType.custom,
    customLabel: 'Parque Sarmiento',
    lat: -31.4,
    lng: -64.1,
    geohash: 'abc12',
  );

  group('trainerProfileComplete getter (ADR-TPO-004)', () {
    test('SCENARIO-694: false when trainerBio is null', () {
      final profile = baseProfile(trainerBio: null, trainerOffersOnline: true);
      expect(profile.trainerProfileComplete, isFalse);
    });

    test('SCENARIO-695: false when trainerSpecialty is null', () {
      final profile =
          baseProfile(trainerSpecialty: null, trainerOffersOnline: true);
      expect(profile.trainerProfileComplete, isFalse);
    });

    test('SCENARIO-696: false when trainerMonthlyRate is null', () {
      final profile =
          baseProfile(trainerMonthlyRate: null, trainerOffersOnline: true);
      expect(profile.trainerProfileComplete, isFalse);
    });

    test(
      'SCENARIO-697: false when all required fields set but '
      'locations empty and online=false',
      () {
        final profile = baseProfile(
          trainerLocations: const [],
          trainerOffersOnline: false,
        );
        expect(profile.trainerProfileComplete, isFalse);
      },
    );

    test(
      'SCENARIO-698: true when all required fields set and online=true',
      () {
        final profile = baseProfile(
          trainerLocations: const [],
          trainerOffersOnline: true,
        );
        expect(profile.trainerProfileComplete, isTrue);
      },
    );

    test(
      'SCENARIO-699: true when all required fields set and locations non-empty',
      () {
        final profile = baseProfile(
          trainerLocations: [kLocation],
          trainerOffersOnline: false,
        );
        expect(profile.trainerProfileComplete, isTrue);
      },
    );

    test(
      'SCENARIO-700: false when all trainer fields null (fresh trainer)',
      () {
        final profile = baseProfile(
          trainerBio: null,
          trainerSpecialty: null,
          trainerMonthlyRate: null,
          trainerLocations: const [],
          trainerOffersOnline: false,
        );
        expect(profile.trainerProfileComplete, isFalse);
      },
    );
  });
}
