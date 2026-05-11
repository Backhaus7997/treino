import 'package:json_annotation/json_annotation.dart';

enum UserRole {
  @JsonValue('athlete')
  athlete,
  @JsonValue('trainer')
  trainer,
}

extension UserRoleX on UserRole {
  static const _wireMap = {
    'athlete': UserRole.athlete,
    'trainer': UserRole.trainer,
  };

  static UserRole fromJson(String value) {
    final role = _wireMap[value];
    if (role == null) {
      throw ArgumentError.value(value, 'value', 'Unknown UserRole wire value');
    }
    return role;
  }

  String toJson() => switch (this) {
        UserRole.athlete => 'athlete',
        UserRole.trainer => 'trainer',
      };
}
