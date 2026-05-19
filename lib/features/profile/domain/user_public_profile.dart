import 'package:freezed_annotation/freezed_annotation.dart';

part 'user_public_profile.freezed.dart';
part 'user_public_profile.g.dart';

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
  }) = _UserPublicProfile;

  factory UserPublicProfile.fromJson(Map<String, Object?> json) =>
      _$UserPublicProfileFromJson(json);
}
