// ignore: unused_import — Timestamp is used by the generated profile_share.g.dart part
import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:freezed_annotation/freezed_annotation.dart';

import '../../profile/data/timestamp_converter.dart';
import '../../profile/domain/experience_level.dart';
import '../../profile/domain/gender.dart';

part 'profile_share.freezed.dart';
part 'profile_share.g.dart';

/// Athlete-to-trainer profile share grant document.
///
/// Stored in `profile_shares/{athleteId}`. The athlete writes this doc when
/// they opt in to share their personal data with a trainer. The trainer reads
/// it from the Resumen tab. The document is the data itself (Option A2 from
/// the exploration) — no separate grant doc needed.
///
/// Mirrors the `session_shares/{athleteId}` pattern: one doc per athlete,
/// one trainerId (all-or-nothing, one-trainer-at-a-time).
///
/// Fields mirror [UserProfile] exactly (same types). Fields that do NOT exist
/// in [UserProfile] (injuries, city) are intentionally absent.
@freezed
class ProfileShare with _$ProfileShare {
  const factory ProfileShare({
    /// The trainer this consent is for.
    required String trainerId,

    // ── Shared personal fields (match UserProfile types exactly) ──────────
    String? phone,
    @TimestampConverter() DateTime? bornAt,
    int? heightCm,
    double? bodyWeightKg,
    Gender? gender,
    ExperienceLevel? experienceLevel,

    /// Last time the athlete updated this document.
    @TimestampConverter() DateTime? updatedAt,
  }) = _ProfileShare;

  factory ProfileShare.fromJson(Map<String, Object?> json) =>
      _$ProfileShareFromJson(json);
}
