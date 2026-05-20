import 'package:freezed_annotation/freezed_annotation.dart';

import 'trainer_specialty.dart';

part 'trainer_public_profile.freezed.dart';
part 'trainer_public_profile.g.dart';

/// Public-facing identity document stored in `trainerPublicProfiles/{uid}`.
///
/// Readable by any authenticated user; writable only by the owner via
/// `UserRepository.update()` dual-write (WriteBatch).
///
/// Fields per design D1. `displayNameLowercase` is derived by
/// `UserRepository._trainerPublicSubsetFromPartial`, NOT by this model.
///
/// REQ-COACH-DISC-DATA-001, REQ-COACH-DISC-DATA-002.
@freezed
class TrainerPublicProfile with _$TrainerPublicProfile {
  const factory TrainerPublicProfile({
    required String uid,
    String? displayName,
    String? displayNameLowercase,
    String? avatarUrl,
    String? trainerBio,
    @JsonKey(
      fromJson: _specialtyFromJson,
      toJson: _specialtyToJson,
    )
    TrainerSpecialty? trainerSpecialty,
    String? trainerGeohash,
    double? trainerLatitude,
    double? trainerLongitude,
    int? trainerMonthlyRate,
  }) = _TrainerPublicProfile;

  factory TrainerPublicProfile.fromJson(Map<String, Object?> json) =>
      _$TrainerPublicProfileFromJson(json);
}

TrainerSpecialty? _specialtyFromJson(Object? value) =>
    trainerSpecialtyFromString(value as String?);

String? _specialtyToJson(TrainerSpecialty? s) =>
    s == null ? null : TrainerSpecialtyX.toWire(s);

// ignore_for_file: invalid_annotation_target
