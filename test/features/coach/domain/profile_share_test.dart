import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/coach/domain/profile_share.dart';
import 'package:treino/features/profile/domain/experience_level.dart';
import 'package:treino/features/profile/domain/gender.dart';

void main() {
  group('ProfileShare', () {
    test('fromJson/toJson round-trip with all fields', () {
      final now = DateTime.utc(2026, 7, 1, 12, 0, 0);
      final bornAt = DateTime.utc(1992, 3, 15);

      final json = <String, Object?>{
        'trainerId': 'trainer-uid-001',
        'phone': '+54 9 11 1234-5678',
        'bornAt': Timestamp.fromDate(bornAt),
        'heightCm': 175,
        'bodyWeightKg': 72.5,
        'gender': 'female',
        'experienceLevel': 'intermediate',
        'updatedAt': Timestamp.fromDate(now),
      };

      final share = ProfileShare.fromJson(json);

      expect(share.trainerId, 'trainer-uid-001');
      expect(share.phone, '+54 9 11 1234-5678');
      expect(share.bornAt, bornAt);
      expect(share.heightCm, 175);
      expect(share.bodyWeightKg, 72.5);
      expect(share.gender, Gender.female);
      expect(share.experienceLevel, ExperienceLevel.intermediate);
      expect(share.updatedAt, now);
    });

    test(
        'fromJson with only trainerId (minimal doc — athlete opted in with no optional fields)',
        () {
      final json = <String, Object?>{'trainerId': 'trainer-uid-001'};
      final share = ProfileShare.fromJson(json);

      expect(share.trainerId, 'trainer-uid-001');
      expect(share.phone, isNull);
      expect(share.bornAt, isNull);
      expect(share.heightCm, isNull);
      expect(share.bodyWeightKg, isNull);
      expect(share.gender, isNull);
      expect(share.experienceLevel, isNull);
      expect(share.updatedAt, isNull);
    });

    test('toJson serializes gender and experienceLevel as wire strings', () {
      final share = ProfileShare(
        trainerId: 'tid',
        gender: Gender.nonBinary,
        experienceLevel: ExperienceLevel.advanced,
      );
      final json = share.toJson();
      expect(json['gender'], 'non_binary');
      expect(json['experienceLevel'], 'advanced');
    });

    test('copyWith preserves unmodified fields', () {
      final share = ProfileShare(
        trainerId: 'tid',
        heightCm: 180,
        bodyWeightKg: 80.0,
      );
      final modified = share.copyWith(heightCm: 181);
      expect(modified.trainerId, 'tid');
      expect(modified.heightCm, 181);
      expect(modified.bodyWeightKg, 80.0);
    });
  });
}
