import 'package:json_annotation/json_annotation.dart';

enum ReactionType {
  @JsonValue('like')
  like,
  @JsonValue('fire')
  fire,
  @JsonValue('clap')
  clap,
}

extension ReactionTypeX on ReactionType {
  static const _wireMap = {
    'like': ReactionType.like,
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
        ReactionType.like => 'like',
        ReactionType.fire => 'fire',
        ReactionType.clap => 'clap',
      };
}
