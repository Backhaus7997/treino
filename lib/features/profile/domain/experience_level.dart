import 'package:json_annotation/json_annotation.dart';

enum ExperienceLevel {
  @JsonValue('beginner')
  beginner,
  @JsonValue('intermediate')
  intermediate,
  @JsonValue('advanced')
  advanced,
}

extension ExperienceLevelX on ExperienceLevel {
  static const _wireMap = {
    'beginner': ExperienceLevel.beginner,
    'intermediate': ExperienceLevel.intermediate,
    'advanced': ExperienceLevel.advanced,
  };

  static ExperienceLevel fromJson(String value) {
    final level = _wireMap[value];
    if (level == null) {
      throw ArgumentError.value(
        value,
        'value',
        'Unknown ExperienceLevel wire value',
      );
    }
    return level;
  }

  String toJson() => switch (this) {
        ExperienceLevel.beginner => 'beginner',
        ExperienceLevel.intermediate => 'intermediate',
        ExperienceLevel.advanced => 'advanced',
      };
}
