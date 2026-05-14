import 'package:json_annotation/json_annotation.dart';

enum FriendshipStatus {
  @JsonValue('pending')
  pending,
  @JsonValue('accepted')
  accepted,
}

extension FriendshipStatusX on FriendshipStatus {
  static const _wireMap = {
    'pending': FriendshipStatus.pending,
    'accepted': FriendshipStatus.accepted,
  };

  static FriendshipStatus fromJson(String value) {
    final status = _wireMap[value];
    if (status == null) {
      throw ArgumentError.value(
        value,
        'value',
        'Unknown FriendshipStatus wire value',
      );
    }
    return status;
  }

  String toJson() => switch (this) {
        FriendshipStatus.pending => 'pending',
        FriendshipStatus.accepted => 'accepted',
      };
}
