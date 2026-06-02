import 'package:freezed_annotation/freezed_annotation.dart';

import 'trainer_location.dart';
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
    // DEPRECATED — singular location campos legacy. Mantenidos por backward
    // compat hasta el cleanup PR. Ver doc del campo equivalente en UserProfile.
    String? trainerGeohash,
    double? trainerLatitude,
    double? trainerLongitude,
    int? trainerMonthlyRate,
    // ── Multi-location (Fase 6 Etapa 0) ────────────────────────────────
    @Default(<TrainerLocation>[]) List<TrainerLocation> trainerLocations,
    @Default(<String>[]) List<String> trainerGeohashes,
    @Default(false) bool trainerOffersOnline,
    // ── Review aggregate (Fase 6 Etapa 7) ──────────────────────────────────
    // Written exclusively by the reviewAggregate Cloud Function.
    // ADR-RV-004: lives on TrainerPublicProfile for O(1) discovery reads.
    // ADR-RV-005: MUST NOT appear in UserRepository._trainerPublicFields.
    double? averageRating,
    @Default(0) int reviewCount,
  }) = _TrainerPublicProfile;

  factory TrainerPublicProfile.fromJson(Map<String, Object?> json) =>
      _$TrainerPublicProfileFromJson(json);
}

TrainerSpecialty? _specialtyFromJson(Object? value) =>
    trainerSpecialtyFromString(value as String?);

String? _specialtyToJson(TrainerSpecialty? s) =>
    s == null ? null : TrainerSpecialtyX.toWire(s);

// ignore_for_file: invalid_annotation_target
