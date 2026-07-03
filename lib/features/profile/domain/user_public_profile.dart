import 'package:freezed_annotation/freezed_annotation.dart';

part 'user_public_profile.freezed.dart';
part 'user_public_profile.g.dart';

/// Defensive non-negative floor for follower/following counters on READ.
///
/// The friendship repo mutates these with atomic `FieldValue.increment(-1)`,
/// which cannot clamp at zero — a drifted counter could persist a negative
/// value. We clamp on deserialization so the model never exposes a negative
/// count to the UI. Null stays null (field simply absent on the doc).
int? _nonNegativeCount(int? raw) => raw == null ? null : (raw < 0 ? 0 : raw);

/// Public-facing identity document stored in `userPublicProfiles/{uid}`.
///
/// Contains ONLY the 5 public fields (uid, displayName, displayNameLowercase,
/// avatarUrl, gymId). All private fields (email, role, timestamps, biometrics)
/// remain exclusively in `users/{uid}`. See design Section D — Field Privacy
/// Classification.
///
/// `displayNameLowercase` is NOT auto-derived by this model — it is the
/// responsibility of `UserRepository`'s private write-path helpers
/// (`_publicSubsetFromProfile`, `_publicSubsetFromPartial`) to derive it.
/// See REQ-UPP-002 / ADR-UPP-11.
@freezed
class UserPublicProfile with _$UserPublicProfile {
  const factory UserPublicProfile({
    required String uid,
    String? displayName,
    String? displayNameLowercase,
    String? avatarUrl,
    String? gymId,

    /// Denormalized composed brand-branch display label (e.g.
    /// "SportClub - Belgrano", or just the brand name for independent
    /// single-branch gyms). Dual-written by `UserRepository.update()`
    /// alongside `gymId` at profile-save time — mirrors `CheckIn.gymName`.
    /// Nullable for backward-compat with profiles saved before this field
    /// existed (also `null` when `gymId` is `null`/`kNoGymId`/unresolvable).
    /// See gyms-foundation Phase 3 (name resolution + denormalization).
    String? gymName,
    int? workoutsCount,
    int? racha,
    // ignore: invalid_annotation_target
    @JsonKey(fromJson: _nonNegativeCount) int? followersCount,
    // ignore: invalid_annotation_target
    @JsonKey(fromJson: _nonNegativeCount) int? followingCount,
    // Opt-in flag a trainer can flip to expose ALL their `trainer-template`
    // routines to their active athletes (a "buffet" the athletes can browse
    // and run sessions from without being explicitly assigned). Defaults to
    // false so existing docs without the field decode safely and no template
    // becomes public retroactively. Off = athletes only see plans the
    // trainer assigned to them one-by-one.
    @Default(false) bool sharedTemplatesWithAthletes,

    // Opt-in flag an athlete controls to expose their ranking metrics
    // (lifetimeVolumeKg, best<Lift>Kg, and the already-public `racha`) on
    // per-gym leaderboards. Defaults to false so existing docs decode safely
    // and no athlete becomes rankable retroactively. Enabling backfills the
    // 4 metric fields below from the athlete's own history; disabling clears
    // them. See design `sdd/rankings/design` — Opt-In Toggle Lifecycle.
    @Default(false) bool rankingOptIn,

    /// Denormalized lifetime training volume in kg, recomputed (not
    /// incremented) over the same bounded window `finish()` already reads,
    /// for idempotency on best-effort retry. Only written when
    /// `rankingOptIn` is true. Defaults to 0 for backward-compat.
    @Default(0) num lifetimeVolumeKg,

    /// Best squat 1RM-proxy weight (kg) across the barbell squat family,
    /// max-merged (never overwritten downward) over the recompute window.
    /// Null when not opted in or no matching lift logged yet.
    num? bestSquatKg,

    /// Best bench press weight (kg) across the barbell bench family,
    /// max-merged over the recompute window. Null when not opted in or no
    /// matching lift logged yet.
    num? bestBenchKg,

    /// Best deadlift weight (kg) across the barbell deadlift family
    /// (conventional + sumo, max of the two), max-merged over the recompute
    /// window. Null when not opted in or no matching lift logged yet.
    num? bestDeadliftKg,
  }) = _UserPublicProfile;

  factory UserPublicProfile.fromJson(Map<String, Object?> json) =>
      _$UserPublicProfileFromJson(json);
}
