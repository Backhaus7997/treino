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
  const factory UserProfile({
    required String uid,
    required String email,
    required String displayName,
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
  }) = _UserProfile;

  factory UserProfile.fromJson(Map<String, Object?> json) =>
      _$UserProfileFromJson(json);
}
