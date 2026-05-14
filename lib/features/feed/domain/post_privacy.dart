import 'package:json_annotation/json_annotation.dart';

enum PostPrivacy {
  @JsonValue('friends')
  friends,
  @JsonValue('gym')
  gym,
  @JsonValue('public')
  public,
}

extension PostPrivacyX on PostPrivacy {
  static const _wireMap = {
    'friends': PostPrivacy.friends,
    'gym': PostPrivacy.gym,
    'public': PostPrivacy.public,
  };

  static PostPrivacy fromJson(String value) {
    final privacy = _wireMap[value];
    if (privacy == null) {
      throw ArgumentError.value(
        value,
        'value',
        'Unknown PostPrivacy wire value',
      );
    }
    return privacy;
  }

  String toJson() => switch (this) {
        PostPrivacy.friends => 'friends',
        PostPrivacy.gym => 'gym',
        PostPrivacy.public => 'public',
      };
}
