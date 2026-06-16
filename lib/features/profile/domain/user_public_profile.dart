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
  }) = _UserPublicProfile;

  factory UserPublicProfile.fromJson(Map<String, Object?> json) =>
      _$UserPublicProfileFromJson(json);
}
