// ignore: unused_import — Timestamp is used by the generated user_profile.g.dart part
import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:freezed_annotation/freezed_annotation.dart';

import '../data/timestamp_converter.dart';
import 'experience_level.dart';
import 'gender.dart';
import 'user_role.dart';

part 'user_profile.freezed.dart';
part 'user_profile.g.dart';

@freezed
class UserProfile with _$UserProfile {
  /// `displayName` is intentionally nullable: signup/signin create the doc
  /// with `null`, and ProfileSetup (Etapa 6) is responsible for populating it.
  /// Etapa 2 signup MUST NOT carry a name — that violates REQ-AUTH-002.
  ///
  /// Trainer-specific fields (`trainerBio`, `trainerSpecialty`,
  /// `trainerLatitude`, `trainerLongitude`, `trainerGeohash`,
  /// `trainerHourlyRate`) son nullable y solo se setean cuando
  /// `role == UserRole.trainer`. La extensión propia del onboarding del
  /// PF llega en Fase 5 Etapa 2 (Discovery). Esta etapa solo agrega los
  /// campos al schema — sin escribirlos.
  const factory UserProfile({
    required String uid,
    required String email,
    required String? displayName,
    required UserRole role,
    @TimestampConverter() required DateTime createdAt,
    @TimestampConverter() required DateTime updatedAt,
    String? gymId,
    double? bodyWeightKg,
    int? heightCm,
    Gender? gender,
    ExperienceLevel? experienceLevel,
    String? avatarUrl,
    @TimestampConverter() DateTime? bornAt,
    // ── Trainer-specific (Fase 5 Etapa 1 foundations) ───────────────────
    String? trainerBio,
    String? trainerSpecialty,
    double? trainerLatitude,
    double? trainerLongitude,
    String? trainerGeohash,
    int? trainerHourlyRate,
  }) = _UserProfile;

  factory UserProfile.fromJson(Map<String, Object?> json) =>
      _$UserProfileFromJson(json);
}
