import 'package:freezed_annotation/freezed_annotation.dart';

import 'friendship.dart';

part 'public_profile_view.freezed.dart';

/// View-model for the public profile screen. Composes denormalized author
/// data (from any `Post` by the target) with the viewer↔target friendship
/// state and a self-visit flag.
///
/// Not serialized — internal view-model only. No fromJson/toJson.
@freezed
class PublicProfileView with _$PublicProfileView {
  const factory PublicProfileView({
    required String authorDisplayName,
    required String? authorAvatarUrl,
    required String? authorGymId,
    required Friendship? friendship,
    required bool isSelf,
    int? workoutsCount,
    int? racha,
    int? followersCount,
    int? followingCount,
  }) = _PublicProfileView;
}
