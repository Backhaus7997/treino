import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/coach/domain/trainer_public_profile.dart';
import 'package:treino/features/coach/domain/trainer_specialty.dart';

void main() {
  // SCENARIO-407: TrainerPublicProfile full JSON roundtrip.
  // SCENARIO-408: roundtrip with all nullable fields null.
  group('TrainerPublicProfile', () {
    test('SCENARIO-407: full JSON roundtrip preserves all fields', () {
      const profile = TrainerPublicProfile(
        uid: 'trainer-1',
        displayName: 'Carlos Pérez',
        displayNameLowercase: 'carlos pérez',
        avatarUrl: 'https://example.com/avatar.jpg',
        trainerBio: 'Especialista en fuerza con 10 años de experiencia.',
        trainerSpecialty: TrainerSpecialty.powerlifting,
        trainerGeohash: '69y7p',
        trainerLatitude: -34.6037,
        trainerLongitude: -58.3816,
        trainerMonthlyRate: 2500,
      );

      final json = profile.toJson();
      final restored = TrainerPublicProfile.fromJson(json);

      expect(restored, equals(profile));
      expect(restored.uid, equals('trainer-1'));
      expect(restored.displayName, equals('Carlos Pérez'));
      expect(restored.displayNameLowercase, equals('carlos pérez'));
      expect(restored.avatarUrl, equals('https://example.com/avatar.jpg'));
      expect(restored.trainerBio,
          equals('Especialista en fuerza con 10 años de experiencia.'));
      expect(restored.trainerSpecialty, equals(TrainerSpecialty.powerlifting));
      expect(restored.trainerGeohash, equals('69y7p'));
      expect(restored.trainerLatitude, equals(-34.6037));
      expect(restored.trainerLongitude, equals(-58.3816));
      expect(restored.trainerMonthlyRate, equals(2500));
    });

    test('SCENARIO-408: roundtrip with all nullable fields null', () {
      const profile = TrainerPublicProfile(
        uid: 'trainer-2',
        displayName: null,
        displayNameLowercase: null,
        avatarUrl: null,
        trainerBio: null,
        trainerSpecialty: null,
        trainerGeohash: null,
        trainerLatitude: null,
        trainerLongitude: null,
        trainerMonthlyRate: null,
      );

      final json = profile.toJson();
      final restored = TrainerPublicProfile.fromJson(json);

      expect(restored, equals(profile));
      expect(restored.uid, equals('trainer-2'));
      expect(restored.displayName, isNull);
      expect(restored.displayNameLowercase, isNull);
      expect(restored.avatarUrl, isNull);
      expect(restored.trainerBio, isNull);
      expect(restored.trainerSpecialty, isNull);
      expect(restored.trainerGeohash, isNull);
      expect(restored.trainerLatitude, isNull);
      expect(restored.trainerLongitude, isNull);
      expect(restored.trainerMonthlyRate, isNull);
    });

    test('trainerSpecialty serializes as wire string in JSON', () {
      const profile = TrainerPublicProfile(
        uid: 'trainer-3',
        trainerSpecialty: TrainerSpecialty.yoga,
      );

      final json = profile.toJson();
      expect(json['trainerSpecialty'], equals('yoga'));
    });

    test('equality is structural (freezed copyWith)', () {
      const a = TrainerPublicProfile(uid: 'u', displayName: 'Alice');
      const b = TrainerPublicProfile(uid: 'u', displayName: 'Alice');
      const c = TrainerPublicProfile(uid: 'u', displayName: 'Bob');

      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });

    test('copyWith works correctly', () {
      const original = TrainerPublicProfile(
          uid: 'u1', displayName: 'Alice', trainerMonthlyRate: 1000);
      final updated = original.copyWith(displayName: 'Alicia');

      expect(updated.uid, equals('u1'));
      expect(updated.displayName, equals('Alicia'));
      expect(updated.trainerMonthlyRate, equals(1000));
    });
  });
}
