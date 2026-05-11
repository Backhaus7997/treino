import 'package:json_annotation/json_annotation.dart';

enum Gender {
  @JsonValue('male')
  male,
  @JsonValue('female')
  female,
  @JsonValue('non_binary')
  nonBinary,
  @JsonValue('undisclosed')
  undisclosed,
}

extension GenderX on Gender {
  static const _wireMap = {
    'male': Gender.male,
    'female': Gender.female,
    'non_binary': Gender.nonBinary,
    'undisclosed': Gender.undisclosed,
  };

  static Gender fromJson(String value) {
    final gender = _wireMap[value];
    if (gender == null) {
      throw ArgumentError.value(value, 'value', 'Unknown Gender wire value');
    }
    return gender;
  }

  String toJson() => switch (this) {
        Gender.male => 'male',
        Gender.female => 'female',
        Gender.nonBinary => 'non_binary',
        Gender.undisclosed => 'undisclosed',
      };
}
