import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/profile/domain/experience_level.dart';
import 'package:treino/features/profile/domain/gender.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';

void main() {
  final fixedDt = DateTime.utc(2026, 5, 11, 13, 30);

  group('UserProfile', () {
    test('SCENARIO-001: required-only roundtrip, nullables all null', () {
      final profile = UserProfile(
        uid: 'uid-1',
        email: 'a@b.com',
        displayName: 'Alice',
        role: UserRole.athlete,
        createdAt: fixedDt,
        updatedAt: fixedDt,
      );

      final json = profile.toJson();
      final decoded = UserProfile.fromJson(json);

      expect(decoded.uid, equals('uid-1'));
      expect(decoded.email, equals('a@b.com'));
      expect(decoded.displayName, equals('Alice'));
      expect(decoded.role, equals(UserRole.athlete));
      expect(decoded.createdAt, equals(fixedDt));
      expect(decoded.updatedAt, equals(fixedDt));
      expect(decoded.gymId, isNull);
      expect(decoded.bodyWeightKg, isNull);
      expect(decoded.heightCm, isNull);
      expect(decoded.gender, isNull);
      expect(decoded.experienceLevel, isNull);
      expect(decoded.avatarUrl, isNull);
      expect(decoded.bornAt, isNull);
    });

    test('SCENARIO-002: all 13 fields populated roundtrip', () {
      final bornAt = DateTime.utc(1990, 3, 15);
      final profile = UserProfile(
        uid: 'uid-2',
        email: 'b@c.com',
        displayName: 'Bob',
        role: UserRole.trainer,
        createdAt: fixedDt,
        updatedAt: fixedDt,
        gymId: 'gym-abc',
        bodyWeightKg: 75.5,
        heightCm: 180,
        gender: Gender.male,
        experienceLevel: ExperienceLevel.advanced,
        avatarUrl: 'https://example.com/avatar.png',
        bornAt: bornAt,
      );

      final decoded = UserProfile.fromJson(profile.toJson());

      expect(decoded.uid, equals('uid-2'));
      expect(decoded.email, equals('b@c.com'));
      expect(decoded.displayName, equals('Bob'));
      expect(decoded.role, equals(UserRole.trainer));
      expect(decoded.createdAt, equals(fixedDt));
      expect(decoded.updatedAt, equals(fixedDt));
      expect(decoded.gymId, equals('gym-abc'));
      expect(decoded.bodyWeightKg, equals(75.5));
      expect(decoded.heightCm, equals(180));
      expect(decoded.gender, equals(Gender.male));
      expect(decoded.experienceLevel, equals(ExperienceLevel.advanced));
      expect(decoded.avatarUrl, equals('https://example.com/avatar.png'));
      expect(decoded.bornAt, equals(bornAt));
    });

    test('SCENARIO-004: raw map with Timestamp for createdAt decodes to DateTime',
        () {
      final ts = Timestamp.fromDate(fixedDt);
      final raw = <String, Object?>{
        'uid': 'uid-3',
        'email': 'c@d.com',
        'displayName': 'Carol',
        'role': 'athlete',
        'createdAt': ts,
        'updatedAt': ts,
      };

      final profile = UserProfile.fromJson(raw);

      expect(profile.createdAt, equals(fixedDt));
      expect(profile.updatedAt, equals(fixedDt));
      expect(profile.createdAt, isA<DateTime>());
    });
  });
}
