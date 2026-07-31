import 'package:json_annotation/json_annotation.dart';

enum ReactionType {
  @JsonValue('strong')
  strong,
  @JsonValue('fire')
  fire,
  @JsonValue('clap')
  clap,
}

extension ReactionTypeX on ReactionType {
  static const _wireMap = {
    'strong': ReactionType.strong,
    'fire': ReactionType.fire,
    'clap': ReactionType.clap,
  };

  static ReactionType fromJson(String value) {
    final type = _wireMap[value];
    if (type == null) {
      throw ArgumentError.value(
        value,
        'value',
        'Unknown ReactionType wire value',
      );
    }
    return type;
  }

  String toJson() => switch (this) {
        ReactionType.strong => 'strong',
        ReactionType.fire => 'fire',
        ReactionType.clap => 'clap',
      };
}
