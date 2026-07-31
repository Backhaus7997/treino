import 'package:json_annotation/json_annotation.dart';

import 'reaction_type.dart';

class ReactionCountsConverter
    implements JsonConverter<Map<ReactionType, int>, Map<String, dynamic>?> {
  const ReactionCountsConverter();

  @override
  Map<ReactionType, int> fromJson(Map<String, dynamic>? json) {
    if (json == null) return const {};

    final result = <ReactionType, int>{};
    for (final MapEntry(:key, :value) in json.entries) {
      if (value is! int) continue;
      try {
        result[ReactionTypeX.fromJson(key)] = value;
      } on ArgumentError {
        // Forward compatibility: older clients ignore reaction types added by
        // a newer backend instead of failing the entire Post deserialization.
      }
    }
    return result;
  }

  @override
  Map<String, int> toJson(Map<ReactionType, int> object) {
    return object.map((type, count) => MapEntry(type.toJson(), count));
  }
}
