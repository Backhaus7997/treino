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
        displayName: null,
        role: UserRole.athlete,
        createdAt: fixedDt,
        updatedAt: fixedDt,
      );

      final json = profile.toJson();
      final decoded = UserProfile.fromJson(json);

      expect(decoded.uid, equals('uid-1'));
      expect(decoded.email, equals('a@b.com'));
      expect(decoded.displayName, isNull);
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

    test('#388: trainerExperienceYears round-trips (and defaults to null)', () {
      final withYears = UserProfile(
        uid: 'uid-exp',
        email: 'pf@b.com',
        displayName: 'Coach',
        role: UserRole.trainer,
        createdAt: fixedDt,
        updatedAt: fixedDt,
        trainerExperienceYears: 7,
      );

      final decoded = UserProfile.fromJson(withYears.toJson());
      expect(decoded.trainerExperienceYears, equals(7));

      final without = UserProfile(
        uid: 'uid-exp-2',
        email: 'pf2@b.com',
        displayName: null,
        role: UserRole.trainer,
        createdAt: fixedDt,
        updatedAt: fixedDt,
      );
      expect(
        UserProfile.fromJson(without.toJson()).trainerExperienceYears,
        isNull,
      );
    });

    test('SCENARIO-001b: displayName can be non-null and round-trips', () {
      final profile = UserProfile(
        uid: 'uid-1b',
        email: 'a@b.com',
        displayName: 'Alice',
        role: UserRole.athlete,
        createdAt: fixedDt,
        updatedAt: fixedDt,
      );

      final decoded = UserProfile.fromJson(profile.toJson());
      expect(decoded.displayName, equals('Alice'));
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

    test(
        'SCENARIO-004: raw map with Timestamp for createdAt decodes to DateTime',
        () {
      final ts = Timestamp.fromDate(fixedDt);
      final raw = <String, Object?>{
        'uid': 'uid-3',
        'email': 'c@d.com',
        'displayName': null,
        'role': 'athlete',
        'createdAt': ts,
        'updatedAt': ts,
      };

      final profile = UserProfile.fromJson(raw);

      expect(profile.createdAt, equals(fixedDt));
      expect(profile.updatedAt, equals(fixedDt));
      expect(profile.createdAt, isA<DateTime>());
      expect(profile.displayName, isNull);
    });

    // ── Trainer-specific fields (Fase 5 Etapa 1 — REQ-COACH-FOUNDATIONS-001) ──

    test('REQ-COACH-FOUNDATIONS-001: trainer fields default to null', () {
      final profile = UserProfile(
        uid: 'uid-1',
        email: 'a@b.com',
        displayName: null,
        role: UserRole.athlete,
        createdAt: fixedDt,
        updatedAt: fixedDt,
      );
      expect(profile.trainerBio, isNull);
      expect(profile.trainerSpecialty, isNull);
      expect(profile.trainerLatitude, isNull);
      expect(profile.trainerLongitude, isNull);
      expect(profile.trainerGeohash, isNull);
      expect(profile.trainerMonthlyRate, isNull);
    });

    test('REQ-COACH-FOUNDATIONS-001: trainer fields round-trip when populated',
        () {
      final profile = UserProfile(
        uid: 'trainer-1',
        email: 't@coach.com',
        displayName: 'Coach Joe',
        role: UserRole.trainer,
        createdAt: fixedDt,
        updatedAt: fixedDt,
        trainerBio: 'Especialista en hipertrofia con 10 años de experiencia',
        trainerSpecialty: 'hipertrofia',
        trainerLatitude: -34.6037,
        trainerLongitude: -58.3816,
        trainerGeohash: '6gycff',
        trainerMonthlyRate: 15000,
      );
      final decoded = UserProfile.fromJson(profile.toJson());
      expect(decoded.trainerBio, equals(profile.trainerBio));
      expect(decoded.trainerSpecialty, equals('hipertrofia'));
      expect(decoded.trainerLatitude, closeTo(-34.6037, 1e-6));
      expect(decoded.trainerLongitude, closeTo(-58.3816, 1e-6));
      expect(decoded.trainerGeohash, equals('6gycff'));
      expect(decoded.trainerMonthlyRate, equals(15000));
    });

    test(
        'REQ-COACH-FOUNDATIONS-001: docs Firestore antiguos sin trainer fields deserializan con nulls',
        () {
      final raw = <String, dynamic>{
        'uid': 'uid-old',
        'email': 'a@b.com',
        'displayName': null,
        'role': 'athlete',
        'createdAt': Timestamp.fromDate(fixedDt),
        'updatedAt': Timestamp.fromDate(fixedDt),
      };
      final profile = UserProfile.fromJson(raw);
      expect(profile.trainerBio, isNull);
      expect(profile.trainerGeohash, isNull);
      expect(profile.trainerMonthlyRate, isNull);
    });

    // ── termsAcceptedAt (QA-AUTH-001, issue #434) ────────────────────────
    group('termsAcceptedAt', () {
      test('defaults to null when omitted', () {
        final profile = UserProfile(
          uid: 'uid-1',
          email: 'a@b.com',
          displayName: null,
          role: UserRole.athlete,
          createdAt: fixedDt,
          updatedAt: fixedDt,
        );
        expect(profile.termsAcceptedAt, isNull);

        final decoded = UserProfile.fromJson(profile.toJson());
        expect(decoded.termsAcceptedAt, isNull);
      });

      test('round-trips through toJson/fromJson when populated', () {
        final acceptedAt = DateTime.utc(2026, 6, 1, 10, 0);
        final profile = UserProfile(
          uid: 'uid-2',
          email: 'b@c.com',
          displayName: null,
          role: UserRole.athlete,
          createdAt: fixedDt,
          updatedAt: fixedDt,
          termsAcceptedAt: acceptedAt,
        );

        final decoded = UserProfile.fromJson(profile.toJson());
        expect(decoded.termsAcceptedAt, equals(acceptedAt));
      });

      test('raw map with a Firestore Timestamp decodes to DateTime', () {
        final acceptedAt = DateTime.utc(2026, 6, 1, 10, 0);
        final raw = <String, Object?>{
          'uid': 'uid-3',
          'email': 'c@d.com',
          'displayName': null,
          'role': 'athlete',
          'createdAt': Timestamp.fromDate(fixedDt),
          'updatedAt': Timestamp.fromDate(fixedDt),
          'termsAcceptedAt': Timestamp.fromDate(acceptedAt),
        };

        final profile = UserProfile.fromJson(raw);
        expect(profile.termsAcceptedAt, equals(acceptedAt));
      });

      test('legacy doc with no termsAcceptedAt key deserializes to null', () {
        final raw = <String, dynamic>{
          'uid': 'uid-legacy',
          'email': 'a@b.com',
          'displayName': null,
          'role': 'athlete',
          'createdAt': Timestamp.fromDate(fixedDt),
          'updatedAt': Timestamp.fromDate(fixedDt),
        };
        final profile = UserProfile.fromJson(raw);
        expect(profile.termsAcceptedAt, isNull);
      });
    });
  });
}
